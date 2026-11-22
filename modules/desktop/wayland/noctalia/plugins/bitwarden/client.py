#!/usr/bin/env python3
"""Thin Noctalia-to-private-cache bridge. Never puts secrets in argv."""
from __future__ import annotations
import json
import os
import pathlib
import socket
import stat
import subprocess
import sys
import time

import backend as bw


def exchange(directory: pathlib.Path, args: list[str]) -> dict:
    path = directory / 'vault.sock'
    st = path.lstat()
    if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise bw.VaultError('Unsafe vault socket permissions')
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(62)
        conn.connect(str(path))
        conn.sendall((json.dumps(args) + '\n').encode())
        data = bytearray()
        while b'\n' not in data:
            part = conn.recv(16384)
            if not part or len(data) + len(part) > 8 * 1024 * 1024:
                raise bw.VaultError('Vault response incomplete or too large')
            data.extend(part)
        return json.loads(bytes(data).split(b'\n', 1)[0])


def run(args: list[str]) -> dict:
    directory = bw.runtime_dir()
    if args[0] == 'prepare':
        try:
            with socket.create_connection(('127.0.0.1', 8087), timeout=0.05):
                legacy = True
        except OSError:
            legacy = False
        return {'ok': True, 'data': {'runtime': str(directory), 'legacyPort': legacy}}
    # The service's timer must not launch an unused vault daemon.
    if args[0] in ('expire', 'lock'):
        try:
            return exchange(directory, args)
        except (FileNotFoundError, ConnectionRefusedError):
            return {'ok': True, 'data': bw.main(args)}
    try:
        return exchange(directory, args)
    except (FileNotFoundError, ConnectionRefusedError):
        # Only one daemon can take daemon.lock. Contending launchers wait for it.
        subprocess.Popen([sys.executable, str(pathlib.Path(__file__).with_name('daemon.py'))],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, close_fds=True, start_new_session=True)
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                return exchange(directory, args)
            except (FileNotFoundError, ConnectionRefusedError):
                time.sleep(0.03)
        raise bw.VaultError('Private vault helper did not start')


if __name__ == '__main__':
    try:
        if not sys.argv[1:]:
            raise bw.VaultError('Missing operation')
        response = run(sys.argv[1:])
        print(json.dumps(response, ensure_ascii=False))
    except (bw.VaultError, ValueError, OSError, json.JSONDecodeError, IndexError) as exc:
        print(json.dumps({'ok': False, 'error': str(exc) if isinstance(exc, bw.VaultError)
                          else 'Private vault helper failed'}))
