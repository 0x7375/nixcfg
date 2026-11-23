#!/usr/bin/env python3
"""Private, single-user Unix-socket vault cache with native Bitwarden serve.

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
import bw_serve

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
        self.expired_session_id: str | None = None
        self._deadline_key: int | None = None
        self._deadline: float | None = None
        self.server = bw_serve.Server(directory)

    def clear(self) -> None:
        self.items.clear()
        self.loaded = False

    def shutdown(self, *, lock: bool = True) -> None:
        if lock and self.server.process is not None and self.server.process.poll() is None:
            try:
                self.server.request('POST', '/lock', timeout=5)
            except bw.VaultError:
                pass
        self.server.stop()
        bw.session_path(self.directory).unlink(missing_ok=True)
        self.clear()

    def session_id(self) -> str:
        # Public identifier for UI invalidation; never send the CLI session token.
        try:
            return str(bw.session_path(self.directory).stat().st_mtime_ns)
        except FileNotFoundError:
            return ''

    def remaining_seconds(self) -> float | None:
        # One monotonic deadline per unlock. On daemon restart, recover the
        # remaining duration from the session file's original mtime.
        try:
            stamp = bw.session_path(self.directory).stat()
        except FileNotFoundError:
            self._deadline_key = None
            self._deadline = None
            return None
        if stamp.st_mtime_ns != self._deadline_key:
            elapsed = max(0.0, time.time() - stamp.st_mtime)
            self._deadline_key = stamp.st_mtime_ns
            self._deadline = time.monotonic() + max(0.0, bw.SESSION_TTL - elapsed)
        assert self._deadline is not None
        return self._deadline - time.monotonic()

    def expire(self) -> bool:
        remaining = self.remaining_seconds()
        if remaining is None:
            if self.server.process is not None:
                self.shutdown()
            return False
        if remaining > 0:
            return False
        self.expired_session_id = self.session_id()
        self.shutdown()
        self.stop = True
        return True

    def check(self) -> None:
        if self.expire() or not bw.session_path(self.directory).exists():
            self.clear()
            raise bw.VaultError('Vault locked')
        if self.server.process is None or self.server.process.poll() is not None:
            # Restarted daemon, or `bw serve` crashed. Never trust the old
            # in-memory cache while the API has lost its unlocked session.
            self.clear()
            raise bw.VaultError('Bitwarden API stopped; unlock again')

    def list_items(self) -> list:
        return sorted((summary(item) for item in self.items.values() if item.get('name')),
                      key=lambda entry: entry['name'].casefold())

    def reload(self) -> None:
        self.check()
        result = bw_serve.result_data(self.server.request('GET', '/list/object/items', timeout=45))
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
        stage = self.directory / 'unlock.stage'
        stage.unlink(missing_ok=True)
        unlock_file = self.directory / 'unlock.cmd'
        try:
            # On a warm reopen the Python cache is sufficient; no CLI requests.
            if bw.session_path(self.directory).exists() and self.server.process is not None:
                try:
                    self.check()
                    if not self.loaded:
                        self.reload()
                    unlock_file.unlink(missing_ok=True)
                    return {'status': 'unlocked', 'items': self.list_items(), 'session_id': self.session_id()}
                except bw.VaultError:
                    self.shutdown()

            # On a daemon restart, try existing BW_SESSION in the persistent
            # serve process. Never silently expose an old plaintext cache.
            if bw.session_path(self.directory).exists():
                try:
                    self.server.start()
                    self.server.ready()
                    self.reload()
                    unlock_file.unlink(missing_ok=True)
                    return {'status': 'unlocked', 'items': self.list_items(), 'session_id': self.session_id()}
                except bw.VaultError:
                    self.shutdown()

            if not unlock_file.exists():
                # Login remains an explicit CLI setup step. Avoid calling
                # bw status here: it takes ~2.5s on the user's installation.
                self.clear()
                return {'status': 'locked', 'items': []}

            # Start the Node CLI *before* the external security-key prompt.
            # Node's startup cost is overlapped with user authentication.
            self.server.start()
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
            # Only after the external prompt has finished, show the spinner.
            bw.private_replace(stage, 'key-prompt-complete')
            self.server.ready(timeout=14)
            started = time.monotonic_ns()
            try:
                outcome = self.server.request('POST', '/unlock', {'password': password}, timeout=22)
            finally:
                password = ''
            unlock_ms = (time.monotonic_ns() - started) // 1_000_000
            # The API usually returns a session in data.raw. Preserve it for
            # infrequent operations without REST equivalents (e.g. JSON export).
            token = None
            if isinstance(outcome, dict):
                token = outcome.get('raw') or outcome.get('session')
                if not token and isinstance(outcome.get('data'), dict):
                    token = outcome['data'].get('raw')
            if not isinstance(token, str) or not token or any(c.isspace() for c in token):
                raise bw.VaultError('Bitwarden serve did not return a CLI session')
            bw.private_replace(bw.session_path(self.directory), token)
            started = time.monotonic_ns()
            self.reload()
            list_ms = (time.monotonic_ns() - started) // 1_000_000
            try:
                bw.private_replace(self.directory / 'startup-timings.json',
                                   json.dumps({'bw_unlock_ms': unlock_ms,
                                               'bw_list_items_ms': list_ms,
                                               'transport': 'unix-serve'}))
            except OSError:
                pass
            return {'status': 'unlocked', 'items': self.list_items(), 'session_id': self.session_id()}
        except Exception:
            # Never leave an unlocked API process behind after an aborted flow.
            self.shutdown()
            raise
        finally:
            stage.unlink(missing_ok=True)

    def handle(self, args: list[str]) -> Any:
        if not args or not isinstance(args, list) or any(not isinstance(a, str) for a in args):
            raise bw.VaultError('Invalid command')
        op = args[0]
        if op == 'protocol':
            return {'version': 4}
        if op == 'stop':
            self.stop = True
            self.shutdown()
            return {'stopping': True}
        if op == 'open':
            return self.open()
        if op == 'expire':
            expired = self.expire()
            active = (bw.session_path(self.directory).exists()
                      and self.server.process is not None
                      and self.server.process.poll() is None)
            if not active:
                # Terminate the Python cache process, not just bw serve, to
                # release retained heap pages after expiry or server failure.
                self.shutdown()
                self.stop = True
            return {'expired': expired, 'unlocked': bool(active)}
        if op == 'probe':
            try:
                self.check()
            except bw.VaultError:
                self.stop = True
                return {'status': 'locked'}
            return {'status': 'unlocked'}
        if op == 'lock':
            self.shutdown()
            self.stop = True
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
                    result = {'value': bw_serve.result_data(self.server.request('GET', '/object/totp/' + bw.item_id(args[1])))}
            else:
                result = {'value': bw.get_field(item, args[2])}
        elif op == 'reveal':
            item = self.item(args[1])
            if args[2] == 'totp':
                seed = (item.get('login') or {}).get('totp')
                try:
                    result = {'value': bw.generate_totp(seed)}
                except bw.VaultError:
                    result = {'value': bw_serve.result_data(self.server.request('GET', '/object/totp/' + bw.item_id(args[1])))}
            else:
                result = {'value': bw.get_field(item, args[2])}
        elif op == 'edit':
            before = self.item(args[1])
            payload = json.loads(bw.consume(self.directory / 'request.json'))
            if payload.get('revision') != before.get('revisionDate'):
                raise bw.VaultError('Item changed since opening; sync before editing')
            changed = bw.patch_item(copy.deepcopy(before), payload.get('changes'))
            output = self.server.request('PUT', '/object/item/' + bw.item_id(args[1]),
                                         changed, timeout=45)
            updated = bw_serve.result_data(output)
            if not isinstance(updated, dict) or updated.get('id') != before['id']:
                # GET is authoritative; the list endpoint may lag after edits.
                updated = bw_serve.result_data(self.server.request('GET', '/object/item/' + bw.item_id(args[1])))
            if not isinstance(updated, dict) or updated.get('id') != before['id']:
                raise bw.VaultError('Bitwarden edit succeeded, but the item could not be reloaded')
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
        elif op == 'export':
            # Only the configured destination path is supplied by the panel.
            # Export uses the existing CLI session; no second key prompt.
            result = bw.export_plaintext(self.directory, args[1])
        elif op == 'sync':
            self.server.request('POST', '/sync', timeout=48)
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


def signal_noctalia_expired(session_id: str | None) -> None:
    if not session_id:
        return
    # One notification after the daemon has locked and dropped its cache.
    # If Noctalia is not running, the backend remains locked regardless.
    try:
        subprocess.run(['noctalia', 'msg', 'plugin', 'me/bitwarden:service',
                        'all', 'vault_expired', session_id],
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=3, check=False)
    except (OSError, subprocess.TimeoutExpired):
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
            # The listener's timeout is adjusted to the *one* expiry deadline.
            inode = path.stat().st_ino
            vault = Vault(directory)
            idle_since = time.monotonic()
            try:
                while True:
                    remaining = vault.remaining_seconds()
                    if remaining is not None and remaining <= 0:
                        vault.expire()
                        break
                    # No session: retire an unused helper after 90 seconds.
                    # Session active: sleep in accept() until the exact deadline
                    # or a client request; no repeated helper processes/ticks.
                    wait = (max(0.001, remaining) if remaining is not None else
                            max(0.001, 90 - (time.monotonic() - idle_since)))
                    listener.settimeout(wait)
                    try:
                        conn, _ = listener.accept()
                    except socket.timeout:
                        if vault.expire():
                            break
                        if vault.remaining_seconds() is None and time.monotonic() - idle_since >= 90:
                            break
                        continue
                    idle_since = time.monotonic()
                    handle_connection(conn, vault)
                    if vault.stop:
                        break
            finally:
                vault.shutdown()
                signal_noctalia_expired(vault.expired_session_id)
                try:
                    if path.is_socket() and path.stat().st_ino == inode:
                        path.unlink()
                except OSError:
                    pass
    finally:
        os.close(fd)


if __name__ == '__main__':
    run()
