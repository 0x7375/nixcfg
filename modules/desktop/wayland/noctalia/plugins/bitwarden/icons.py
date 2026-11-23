#!/usr/bin/env python3
"""Opt-in Bitwarden website icon cache, never part of the vault request path.

Only the official Bitwarden icon endpoint is contacted. Hostnames and icons
are not put on argv, in the Noctalia state, or in persistent plugin settings.
Icons live in a private persistent XDG cache directory.
"""
from __future__ import annotations

import concurrent.futures
import hashlib
import ipaddress
import json
import os
import pathlib
import re
import stat
import struct
import sys
import tempfile
import urllib.error
import urllib.request

import backend as bw
import client

MAX_ICON = 256 * 1024
MAX_HOSTS = 20  # Per-worker batch cap; the panel processes every displayed result.


def private_directory(path: pathlib.Path) -> pathlib.Path:
    """Ensure a user-owned private directory, including an impermanence symlink.

    NixOS/home-manager may arrange persistent caches as symlinks. Validate the
    resolved target rather than rejecting a trusted user-owned symlink.
    """
    path.mkdir(parents=True, mode=0o700, exist_ok=True)
    resolved = path.resolve(strict=True)
    st = resolved.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        raise bw.VaultError('Icon cache is not owned by the current user')
    if st.st_mode & 0o077:
        # These directories contain hashes of visited domains; keep them private.
        # Existing XDG/impermanence directories may have been created as 0755.
        os.chmod(resolved, stat.S_IMODE(st.st_mode) & ~0o077)
        if resolved.stat().st_mode & 0o077:
            raise bw.VaultError('Icon cache directory is not private')
    return resolved


def cache_directory() -> pathlib.Path:
    """Private persistent cache, with an absolute canonical path for ui.image."""
    base = os.environ.get('XDG_CACHE_HOME')
    root = pathlib.Path(base) if base else pathlib.Path.home() / '.cache'
    if not root.is_absolute():
        raise bw.VaultError('XDG_CACHE_HOME must be an absolute path')
    root.mkdir(parents=True, mode=0o700, exist_ok=True)
    return private_directory(private_directory(root / 'noctalia-bitwarden') / 'icons')


def choose_cache() -> tuple[pathlib.Path, str | None]:
    """Keep icons usable if an existing persistent cache cannot be fixed."""
    try:
        return cache_directory(), None
    except (bw.VaultError, OSError, ValueError) as exc:
        fallback = private_directory(bw.runtime_dir() / 'icons')
        return fallback, f'Persistent icon cache unavailable ({exc}); using temporary cache'


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
    if path.exists() or path.is_symlink():
        st = path.lstat()
        if (stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid()
                and not st.st_mode & 0o077 and 24 <= st.st_size <= MAX_ICON):
            return str(path)
        # Do not trust a pre-existing symlink or an untrusted cache file.
        return None
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


def run(ids: list[str], cache: pathlib.Path | None = None,
        metrics: dict | None = None) -> dict[str, str]:
    ids = [bw.item_id(item_id) for item_id in ids[:MAX_HOSTS]]
    directory = bw.runtime_dir()
    cache = cache if cache is not None else cache_directory()
    response = client.exchange(directory, ['icon_hosts', *ids])
    if not response.get('ok'):
        raise bw.VaultError('Could not look up icon hostnames in the vault daemon')
    hosts = response.get('data') or {}
    valid = {ident: valid_host(host) for ident, host in hosts.items() if ident in ids}
    valid = {ident: host for ident, host in valid.items() if host}
    unique = set(valid.values())
    if metrics is not None:
        metrics.update(requested=len(ids), eligible=len(valid), domains=len(unique))
    found = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = {pool.submit(fetch, host, cache): host for host in unique}
        for task in concurrent.futures.as_completed(jobs):
            try:
                found[jobs[task]] = task.result()
            except (OSError, ValueError):
                continue
    result = {ident: found[host] for ident, host in valid.items() if found.get(host)}
    if metrics is not None:
        metrics['available'] = len(result)
    return result


def diagnose() -> dict:
    """No vault data, passwords, or private hostnames in diagnostics."""
    cache, warning = choose_cache()
    sample = cache / (hashlib.sha256(b'github.com').hexdigest() + '.png')
    result = {'cache_dir': str(cache), 'persistent': warning is None,
              'cached_pngs': len(list(cache.glob('*.png'))),
              'sample_cached': sample.is_file()}
    if warning:
        result['warning'] = warning
    request = urllib.request.Request('https://icons.bitwarden.net/github.com/icon.png',
                                     headers={'Accept': 'image/png'})
    try:
        with opener.open(request, timeout=4) as response:
            raw = response.read(24)
        result['network_probe'] = 'PNG received' if raw.startswith(b'\x89PNG\r\n\x1a\n') else 'Unexpected image format'
    except (OSError, urllib.error.URLError, ValueError) as exc:
        result['network_probe'] = f'{type(exc).__name__}: {exc}'
    return result


if __name__ == '__main__':
    if sys.argv[1:] == ['--diagnose']:
        try:
            print(json.dumps(diagnose()))
        except (bw.VaultError, OSError, ValueError) as exc:
            print(json.dumps({'error': f'Icon diagnostics failed: {exc}'}))
    else:
        try:
            cache, warning = choose_cache()
            metrics = {}
            results = run(sys.argv[1:], cache, metrics)
            output = {'icons': results, 'cache_dir': str(cache), 'stats': metrics}
            if warning:
                output['warning'] = warning
            print(json.dumps(output))
        except (bw.VaultError, OSError, ValueError) as exc:
            print(json.dumps({'icons': {}, 'error': f'Icon worker failed: {exc}'}))
