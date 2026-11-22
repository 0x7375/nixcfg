#!/usr/bin/env python3
"""Private, single-user Unix-socket vault cache.

Keeps plaintext items only in this process's memory, not on disk or in panel state.
The socket is not exposed over TCP. Same-UID processes are not a security boundary.
"""
from __future__ import annotations

import copy
import fcntl
import json
import os
import re
from urllib.parse import urlsplit
import pathlib
import socket
import stat
import subprocess
import time
from typing import Any

import backend as bw

MAX_MESSAGE = 1024 * 1024
SOCKET_NAME = 'vault.sock'


def summary(item: dict) -> dict:
    hints = []
    login = item.get('login') or {}
    if login.get('username'):
        hints.append(login['username'])
    for uri in login.get('uris') or []:
        if isinstance(uri, dict) and uri.get('uri'):
            hints.append(uri['uri'])
            break
    if item.get('type') == 3:
        card = item.get('card') or {}
        hints.extend(str(card[k]) for k in ('brand', 'cardholderName') if card.get(k))
    elif item.get('type') == 4:
        identity = item.get('identity') or {}
        hints.extend(str(identity[k]) for k in ('email', 'firstName', 'lastName') if identity.get(k))
    return {'id': item['id'], 'name': item.get('name') or '', 'type': item.get('type') or 0,
            'subtitle': ' · '.join(hints[:2]), 'search': ' '.join([item.get('name') or '', *hints])}


class Vault:
    def __init__(self, directory: pathlib.Path):
        self.directory = directory
        self.items: dict[str, dict] = {}
        self.loaded = False
        self.stop = False

    def clear(self) -> None:
        self.items.clear()
        self.loaded = False

    def check(self) -> None:
        if bw.expire(self.directory) or not bw.session_path(self.directory).exists():
            self.clear()
            raise bw.VaultError('Vault locked')

    def list_items(self) -> list:
        return sorted((summary(item) for item in self.items.values() if item.get('name')),
                      key=lambda entry: entry['name'].casefold())

    def reload(self) -> None:
        self.check()
        result = json.loads(bw.cli(['list', 'items'], self.directory, timeout=52))
        if not isinstance(result, list):
            raise bw.VaultError('Invalid vault response')
        updated = {item['id']: item for item in result if isinstance(item, dict) and item.get('id')}
        self.items = updated
        self.loaded = True

    def item(self, ident: str) -> dict:
        self.check()
        if not self.loaded:
            self.reload()
        entry = self.items.get(bw.item_id(ident))
        if entry is None:
            raise bw.VaultError('Item not found. Sync to refresh the vault.')
        return entry

    def open(self) -> dict:
        # A warm vault is returned without invoking bw, including on panel reopen.
        if bw.session_path(self.directory).exists():
            try:
                self.check()
                if not self.loaded:
                    self.reload()
                bw.touch(self.directory)
                (self.directory / 'unlock.cmd').unlink(missing_ok=True)
                return {'status': 'unlocked', 'items': self.list_items()}
            except bw.VaultError:
                # Stale session (e.g. after a CLI logout): try the normal unlock.
                bw.session_path(self.directory).unlink(missing_ok=True)
                self.clear()

        unlock_file = self.directory / 'unlock.cmd'
        if not unlock_file.exists():
            state = json.loads(bw.cli(['status'], self.directory, session=False, timeout=17))
            actual = state.get('status')
            self.clear()
            return {'status': 'unauthenticated' if actual == 'unauthenticated' else 'locked', 'items': []}

        # Cold start: skip 'bw status' when an unlock command is available.
        # bw unlock itself validates the account's CLI login state.
        command = bw.consume(unlock_file).strip()
        if not command:
            raise bw.VaultError('Decrypt command not configured')
        try:
            result = subprocess.run(['/bin/sh', '-c', command], capture_output=True,
                                    text=True, timeout=40, check=False)
        except subprocess.TimeoutExpired as exc:
            raise bw.VaultError('Security-key command timed out') from exc
        if result.returncode:
            raise bw.VaultError('Security-key command failed or was cancelled')
        password = result.stdout.rstrip('\r\n')
        if not password:
            raise bw.VaultError('Security-key command returned no password')
        token = bw.cli(['unlock', '--passwordfile', '/dev/stdin', '--raw'], self.directory,
                       stdin=password + '\n', session=False, timeout=20).strip()
        password = ''
        if not token or any(c.isspace() for c in token):
            raise bw.VaultError('Bitwarden did not return a session')
        bw.private_replace(bw.session_path(self.directory), token)
        try:
            self.reload()
        except Exception:
            self.clear()
            raise
        bw.touch(self.directory)
        return {'status': 'unlocked', 'items': self.list_items()}

    def handle(self, args: list[str]) -> Any:
        if not args or not isinstance(args, list) or any(not isinstance(a, str) for a in args):
            raise bw.VaultError('Invalid command')
        op = args[0]
        if op == 'stop':
            self.stop = True
            self.clear()
            return {'stopping': True}
        if op == 'open':
            return self.open()
        if op == 'expire':
            expired = bw.expire(self.directory)
            if expired or not bw.session_path(self.directory).exists():
                self.clear()
            return {'expired': expired}
        if op == 'lock':
            try:
                if bw.session_path(self.directory).exists():
                    bw.cli(['lock'], self.directory, timeout=17)
            finally:
                bw.session_path(self.directory).unlink(missing_ok=True)
                self.clear()
            return {'status': 'locked'}
        self.check()
        if op == 'list':
            if not self.loaded:
                self.reload()
            result = self.list_items()
        elif op == 'icon_hosts':
            # Only item IDs cross process boundaries; the icon worker learns
            # hostnames through the private Unix socket, never through argv.
            result = {}
            for ident in args[1:21]:
                item = self.item(ident)
                for uri in (item.get('login') or {}).get('uris') or []:
                    if not isinstance(uri, dict):
                        continue
                    value = uri.get('uri') or ''
                    if not isinstance(value, str) or any(c.isspace() for c in value):
                        continue
                    parsed = urlsplit(value if '://' in value else 'https://' + value)
                    if parsed.scheme not in ('http', 'https'):
                        continue
                    host = parsed.hostname
                    if host and re.fullmatch(r'[a-zA-Z0-9.-]{1,253}', host):
                        result[ident] = host
                        break
        elif op == 'detail':
            result = bw.describe(self.item(args[1]))
        elif op == 'copy':
            item = self.item(args[1])
            if args[2] == 'totp':
                seed = (item.get('login') or {}).get('totp')
                try:
                    result = {'value': bw.generate_totp(seed)}
                except bw.VaultError:
                    # Preserve Bitwarden-specific formats through the official CLI.
                    result = {'value': bw.cli(['get', 'totp', bw.item_id(args[1])], self.directory).strip()}
            else:
                result = {'value': bw.get_field(item, args[2])}
        elif op == 'reveal':
            item = self.item(args[1])
            if args[2] == 'totp':
                seed = (item.get('login') or {}).get('totp')
                try:
                    result = {'value': bw.generate_totp(seed)}
                except bw.VaultError:
                    result = {'value': bw.cli(['get', 'totp', bw.item_id(args[1])], self.directory).strip()}
            else:
                result = {'value': bw.get_field(item, args[2])}
        elif op == 'edit':
            before = self.item(args[1])
            payload = json.loads(bw.consume(self.directory / 'request.json'))
            if payload.get('revision') != before.get('revisionDate'):
                raise bw.VaultError('Item changed since opening; sync before editing')
            changed = bw.patch_item(copy.deepcopy(before), payload.get('changes'))
            import base64
            encoded = base64.b64encode(json.dumps(changed, ensure_ascii=False, separators=(',', ':')).encode()).decode()
            output = bw.cli(['edit', 'item', bw.item_id(args[1])], self.directory, stdin=encoded + '\n', timeout=52)
            try:
                updated = json.loads(output)
                if not isinstance(updated, dict) or updated.get('id') != before['id']:
                    raise ValueError('No updated item returned')
            except (ValueError, TypeError):
                # Do not assume a revision; a fresh get is required when the CLI
                # returns no usable JSON.
                updated = bw.load_item(self.directory, args[1])
            self.items[updated['id']] = updated
            result = {'detail': bw.describe(updated), 'summary': summary(updated)}
        elif op == 'create':
            payload = json.loads(bw.consume(self.directory / 'request.json'))
            # Reuse validation; create_item returns the new id but not the item.
            info = bw.create_item(self.directory, payload)
            if not info.get('id'):
                self.reload()
                raise bw.VaultError('Item created, but server did not return an item ID. Vault refreshed.')
            updated = info.get('item') or {}
            if not isinstance(updated, dict) or not updated.get('id'):
                updated = bw.load_item(self.directory, info['id'])
            self.items[updated['id']] = updated
            result = {'detail': bw.describe(updated), 'summary': summary(updated)}
        elif op == 'sync':
            bw.cli(['sync'], self.directory, timeout=52)
            self.reload()
            result = self.list_items()
        elif op == 'autotype':
            # Allow typing after closing the panel; uses cached secret.
            item = self.item(args[1])
            result = cached_autotype(item)
        elif op == 'generate':
            cmd = (['generate', '--passphrase', '--words', '6', '--separator', '-']
                   if len(args) > 1 and args[1] == 'passphrase' else
                   ['generate', '--length', '20', '--uppercase', '--lowercase', '--number', '--special'])
            result = {'value': bw.cli(cmd, self.directory).strip()}
        else:
            raise bw.VaultError('Unsupported command')
        bw.touch(self.directory)
        return result


def cached_autotype(item: dict) -> dict:
    login = item.get('login') or {}
    if item.get('type') != 1:
        raise bw.VaultError('Only logins support autotype')
    username, password = login.get('username') or '', login.get('password') or ''
    if not username and not password:
        raise bw.VaultError('No login fields')
    time.sleep(0.45)
    for i, value in enumerate([username, password]):
        if i == 1 and username and password:
            subprocess.run(['wtype', '-k', 'Tab'], timeout=5, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if value:
            subprocess.run(['wtype', '-'], input=value, text=True, timeout=15, check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {'typed': True}


def handle_connection(conn: socket.socket, vault: Vault) -> None:
    with conn:
        # Linux credential check even if the parent directory/socket are private.
        if hasattr(socket, 'SO_PEERCRED'):
            import struct
            creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12)
            _pid, uid, _gid = struct.unpack('3i', creds)
            if uid != os.getuid():
                return
        conn.settimeout(65)
        try:
            raw = bytearray()
            while b'\n' not in raw:
                part = conn.recv(8192)
                if not part or len(raw) + len(part) > MAX_MESSAGE:
                    raise bw.VaultError('Oversized or incomplete request')
                raw.extend(part)
            args = json.loads(bytes(raw).split(b'\n', 1)[0])
            data = vault.handle(args)
            response = {'ok': True, 'data': data}
        except (bw.VaultError, IndexError, ValueError, OSError, TypeError, KeyError,
                json.JSONDecodeError, subprocess.SubprocessError) as exc:
            response = {'ok': False, 'error': str(exc) if isinstance(exc, bw.VaultError)
                        else 'Bitwarden operation failed'}
        try:
            conn.sendall((json.dumps(response, ensure_ascii=False) + '\n').encode())
        except (OSError, socket.timeout):
            pass


def run() -> None:
    os.umask(0o077)
    directory = bw.runtime_dir()
    lock_path = directory / 'daemon.lock'
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        if os.fstat(fd).st_uid != os.getuid() or os.fstat(fd).st_mode & 0o077:
            return
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        path = directory / SOCKET_NAME
        if path.exists() or path.is_socket() or path.is_symlink():
            st = path.lstat()
            if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid():
                return
            path.unlink()  # Safe after acquiring the singleton flock.
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
            listener.bind(str(path))
            os.chmod(path, 0o600)
            listener.listen(8)
            listener.settimeout(30)
            inode = path.stat().st_ino
            vault = Vault(directory)
            idle_since = time.monotonic()
            try:
                while True:
                    try:
                        conn, _ = listener.accept()
                    except socket.timeout:
                        if bw.expire(directory):
                            vault.clear()
                        if not bw.session_path(directory).exists() and time.monotonic() - idle_since > 90:
                            break
                        continue
                    idle_since = time.monotonic()
                    handle_connection(conn, vault)
                    if vault.stop:
                        break
            finally:
                vault.clear()
                try:
                    if path.is_socket() and path.stat().st_ino == inode:
                        path.unlink()
                except OSError:
                    pass
    finally:
        os.close(fd)


if __name__ == '__main__':
    run()
