#!/usr/bin/env python3
"""Owner-only Unix-domain socket transport for Bitwarden's native `bw serve`.

Requires Bitwarden CLI >= 2025.10.0. No TCP fallback and no HTTP listener on
127.0.0.1; the socket and its parent directory are both private to the user.
"""
from __future__ import annotations

import ctypes
import http.client
import json
import os
import pathlib
import signal
import socket
import stat
import subprocess
import time
from typing import Any

import backend as bw

SOCKET_NAME = "bw-api.sock"
MAX_RESPONSE = 64 * 1024 * 1024


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path: pathlib.Path, timeout: float):
        super().__init__("localhost", 8087, timeout=timeout)
        self.socket_path = str(path)

    def connect(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.settimeout(self.timeout)
            sock.connect(self.socket_path)
            self.sock = sock
        except BaseException:
            sock.close()
            raise


def _check_socket(path: pathlib.Path) -> None:
    st = path.lstat()
    if not stat.S_ISSOCK(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise bw.VaultError("Unsafe Bitwarden API socket")
    root = path.parent.lstat()
    if not stat.S_ISDIR(root.st_mode) or root.st_uid != os.getuid() or root.st_mode & 0o077:
        raise bw.VaultError("Unsafe Bitwarden API directory")


def call(path: pathlib.Path, method: str, endpoint: str, body: Any = None, *, timeout: float = 18) -> Any:
    """Perform one local HTTP request; check API success, never echo secret errors."""
    if method not in ("GET", "POST", "PUT") or not endpoint.startswith("/") or "//" in endpoint:
        raise bw.VaultError("Invalid Bitwarden API operation")
    _check_socket(path)
    payload = None if body is None else json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode()
    headers = {"Host": "localhost:8087", "Accept": "application/json", "Connection": "close"}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    conn = UnixHTTPConnection(path, timeout)
    try:
        conn.request(method, endpoint, body=payload, headers=headers)
        response = conn.getresponse()
        raw = response.read(MAX_RESPONSE + 1)
        if len(raw) > MAX_RESPONSE:
            raise bw.VaultError("Bitwarden response too large")
        if response.status >= 400:
            raise bw.VaultError(f"Bitwarden API failed (HTTP {response.status})")
        envelope = json.loads(raw)
        if not isinstance(envelope, dict) or envelope.get("success") is not True:
            raise bw.VaultError("Bitwarden API rejected the operation")
        return envelope.get("data")
    except (ConnectionError, TimeoutError, OSError, http.client.HTTPException,
            json.JSONDecodeError) as exc:
        raise bw.VaultError("Bitwarden API unavailable or returned invalid data") from exc
    finally:
        conn.close()


def result_data(value: Any) -> Any:
    """Bitwarden's API envelopes often wrap the requested payload in data.data."""
    if isinstance(value, dict) and "data" in value:
        return value["data"]
    return value


def _terminate_with_parent() -> None:
    """Linux parent-death notification, to avoid leaving an unlocked serve orphan."""
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(1, signal.SIGTERM, 0, 0, 0) != 0:
        os._exit(127)
    if os.getppid() == 1:
        os._exit(127)


class Server:
    def __init__(self, directory: pathlib.Path):
        self.directory = directory
        self.path = directory / SOCKET_NAME
        self.process: subprocess.Popen | None = None

    def start(self) -> None:
        if self.process is not None and self.process.poll() is None:
            return
        # A crashed prior daemon may leave its socket pathname behind.
        # Our caller holds daemon.lock; only unlink a dead socket belonging
        # to our UID, not an active listener or a symlink.
        if self.path.exists() or self.path.is_symlink() or self.path.is_socket():
            _check_socket(self.path)
            try:
                probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                try:
                    probe.settimeout(0.4)
                    probe.connect(str(self.path))
                finally:
                    probe.close()
            except (ConnectionRefusedError, FileNotFoundError):
                self.path.unlink()
            except OSError as exc:
                raise bw.VaultError("Existing Bitwarden API socket is unavailable") from exc
            else:
                raise bw.VaultError("Another Bitwarden API is already running")
        if len(os.fsencode(str(self.path))) >= 100:
            raise bw.VaultError("Bitwarden API socket path too long")
        env = os.environ.copy()
        env.pop("BW_PASSWORD", None)
        env.pop("BW_SESSION", None)
        # CLI may reuse the previous session after the plugin daemon restarts.
        saved = bw.session_path(self.directory)
        if saved.exists():
            env["BW_SESSION"] = bw.secure_read(saved, max_bytes=4096).strip()
        try:
            self.process = subprocess.Popen(
                ["bw", "serve", "--hostname", "unix://" + str(self.path)],
                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, close_fds=True, env=env,
                preexec_fn=_terminate_with_parent,
            )
        except (FileNotFoundError, OSError) as exc:
            raise bw.VaultError("Unable to start Bitwarden serve") from exc

    def ready(self, *, timeout: float = 12) -> None:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.process is None or self.process.poll() is not None:
                raise bw.VaultError("Bitwarden serve exited during startup")
            if self.path.is_socket():
                # Node creates with the daemon's umask (0077). Tighten mode.
                os.chmod(self.path, 0o600)
                _check_socket(self.path)
                try:
                    call(self.path, "GET", "/status", timeout=0.7)
                    return
                except bw.VaultError:
                    pass
            time.sleep(0.05)
        raise bw.VaultError("Bitwarden serve did not become ready")

    def request(self, method: str, endpoint: str, body: Any = None, *, timeout: float = 18) -> Any:
        if self.process is None or self.process.poll() is not None:
            raise bw.VaultError("Bitwarden serve is not running")
        return call(self.path, method, endpoint, body, timeout=timeout)

    def stop(self) -> None:
        proc = self.process
        self.process = None
        if proc is not None:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
        if self.path.is_socket():
            st = self.path.lstat()
            if st.st_uid == os.getuid():
                self.path.unlink()
