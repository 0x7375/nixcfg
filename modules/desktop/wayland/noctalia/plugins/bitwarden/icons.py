#!/usr/bin/env python3
"""Opt-in Bitwarden website icon cache, never part of the vault request path.

Only the official Bitwarden icon endpoint is contacted. Hostnames and icons
are not put on argv, in the Noctalia state, or in persistent plugin settings.
Icons live in the private XDG_RUNTIME_DIR and disappear on reboot.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import struct
import sys
import tempfile
import urllib.error
import urllib.request

import backend as bw
import client

MAX_ICON = 256 * 1024
MAX_HOSTS = 20


class DenyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


opener = urllib.request.build_opener(DenyRedirect)


def valid_host(name: object) -> str | None:
    if not isinstance(name, str) or len(name) > 253:
        return None
    host = name.strip('.').lower()
    if not re.fullmatch(r'[a-z0-9.-]+', host) or '..' in host or '.' not in host:
        return None
    if host.endswith(('.local', '.internal', '.localhost', '.onion', '.test', '.invalid', '.example')):
        return None
    try:
        ipaddress.ip_address(host)
        return None
    except ValueError:
        pass
    return host


def fetch(host: str, directory: pathlib.Path) -> str | None:
    digest = hashlib.sha256(host.encode('ascii')).hexdigest()
    path = directory / (digest + '.png')
    if path.is_file():
        return str(path)
    # Prevent request URLs from being redirected to arbitrary external sites.
    request = urllib.request.Request('https://icons.bitwarden.net/' + host + '/icon.png',
                                     headers={'Accept': 'image/png'})
    try:
        with opener.open(request, timeout=4) as response:
            raw = response.read(MAX_ICON + 1)
    except (OSError, urllib.error.URLError, ValueError):
        return None
    if len(raw) > MAX_ICON or len(raw) < 24 or not raw.startswith(b'\x89PNG\r\n\x1a\n'):
        return None
    if raw[12:16] != b'IHDR':
        return None
    width, height = struct.unpack('>II', raw[16:24])
    if not 1 <= width <= 1024 or not 1 <= height <= 1024:
        return None
    fd, tmp = tempfile.mkstemp(prefix='.icon-', dir=directory)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    return str(path)


def run(ids: list[str]) -> dict[str, str]:
    ids = [bw.item_id(item_id) for item_id in ids[:MAX_HOSTS]]
    directory = bw.runtime_dir()
    cache = directory / 'icons'
    cache.mkdir(mode=0o700, exist_ok=True)
    if cache.is_symlink() or cache.stat().st_uid != os.getuid() or cache.stat().st_mode & 0o077:
        raise bw.VaultError('Unsafe icon directory')
    response = client.exchange(directory, ['icon_hosts', *ids])
    if not response.get('ok'):
        return {}
    hosts = response.get('data') or {}
    valid = {ident: valid_host(host) for ident, host in hosts.items() if ident in ids}
    valid = {ident: host for ident, host in valid.items() if host}
    unique = set(valid.values())
    found = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = {pool.submit(fetch, host, cache): host for host in unique}
        for task in concurrent.futures.as_completed(jobs):
            try:
                found[jobs[task]] = task.result()
            except (OSError, ValueError):
                continue
    return {ident: found[host] for ident, host in valid.items() if found.get(host)}


if __name__ == '__main__':
    try:
        print(json.dumps({'icons': run(sys.argv[1:])}))
    except (bw.VaultError, OSError, ValueError) as exc:
        print(json.dumps({'icons': {}}))
