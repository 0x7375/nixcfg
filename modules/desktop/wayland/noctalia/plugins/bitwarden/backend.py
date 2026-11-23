#!/usr/bin/env python3
"""Noctalia Bitwarden adapter. No TCP listener; secrets are never command arguments.

The only files containing secrets are short-lived, mode-0600 request files and
an expiring CLI session in the user-owned XDG runtime directory (tmpfs on Linux).
The existing user-defined decrypt command runs only on unlock.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import pathlib
import re
import stat
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import parse_qs, urlsplit

SESSION_TTL = 15 * 60
MAX_PAYLOAD = 1024 * 1024
ID_RE = re.compile(r"^[0-9A-Za-z-]{8,100}$")


class VaultError(Exception):
    pass


def runtime_dir() -> pathlib.Path:
    root = os.environ.get("XDG_RUNTIME_DIR")
    if not root:
        raise VaultError("XDG_RUNTIME_DIR is required; refusing to store a session on disk")
    base = pathlib.Path(root)
    if not base.is_dir() or base.is_symlink() or base.stat().st_uid != os.getuid():
        raise VaultError("Unsafe XDG_RUNTIME_DIR")
    if base.stat().st_mode & 0o077:
        raise VaultError("XDG_RUNTIME_DIR must be private (0700)")
    directory = base / f"noctalia-bitwarden-{os.getuid()}"
    try:
        directory.mkdir(mode=0o700, exist_ok=True)
    except OSError as exc:
        raise VaultError("Cannot create private runtime directory") from exc
    st = directory.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise VaultError("Unsafe Bitwarden runtime directory")
    return directory


def secure_read(path: pathlib.Path, *, max_bytes: int = MAX_PAYLOAD) -> str:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise VaultError("Unsafe private file permissions")
    if st.st_size > max_bytes:
        raise VaultError("Request too large")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        with os.fdopen(fd, "rb") as file:
            raw = file.read(max_bytes + 1)
    except Exception:
        raise
    if len(raw) > max_bytes:
        raise VaultError("Request too large")
    return raw.decode("utf-8")


def consume(path: pathlib.Path) -> str:
    try:
        return secure_read(path)
    finally:
        path.unlink(missing_ok=True)


def private_replace(path: pathlib.Path, contents: str) -> None:
    fd, temp = tempfile.mkstemp(prefix=".session-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as file:
            file.write(contents)
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def session_path(directory: pathlib.Path) -> pathlib.Path:
    return directory / "session"


def cli(args: list[str], directory: pathlib.Path, *, stdin: str | None = None,
        session: bool = True, timeout: int = 40) -> str:
    env = os.environ.copy()
    env.pop("BW_SESSION", None)
    env.pop("BW_PASSWORD", None)
    if session:
        key = secure_read(session_path(directory), max_bytes=4096).strip()
        if not key:
            raise VaultError("Vault locked")
        env["BW_SESSION"] = key
    try:
        completed = subprocess.run(["bw", *args], input=stdin, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   env=env, timeout=timeout, check=False)
    except FileNotFoundError as exc:
        raise VaultError("Bitwarden CLI (bw) not found") from exc
    except subprocess.TimeoutExpired as exc:
        raise VaultError("Bitwarden CLI timed out") from exc
    if completed.returncode:
        # Do not put CLI stderr in a persistent Noctalia log, or echo it to the UI.
        raise VaultError("Bitwarden command failed (vault locked, offline or permission denied)")
    return completed.stdout


def expire(directory: pathlib.Path) -> bool:
    path = session_path(directory)
    if not path.exists():
        return False
    if time.time() - path.lstat().st_mtime < SESSION_TTL:
        return False
    try:
        cli(["lock"], directory, timeout=15)
    except VaultError:
        pass
    path.unlink(missing_ok=True)
    return True


def require_unlocked(directory: pathlib.Path) -> None:
    if expire(directory) or not session_path(directory).exists():
        raise VaultError("Vault locked")


def touch(directory: pathlib.Path) -> None:
    os.utime(session_path(directory), None)


def item_id(value: str) -> str:
    if not ID_RE.fullmatch(value):
        raise VaultError("Invalid item ID")
    return value


def load_item(directory: pathlib.Path, ident: str) -> dict:
    item = json.loads(cli(["get", "item", item_id(ident)], directory))
    if not isinstance(item, dict):
        raise VaultError("Invalid item")
    return item


def row(rows: list, key: str, label: str, value: object = "", hidden: bool = False,
        linked: bool = False) -> None:
    if value is None or value == "":
        return
    rows.append({"key": key, "label": label, "value": "Linked field" if linked else "••••••••" if hidden else str(value),
                 "hidden": hidden or linked})


def describe(item: dict) -> dict:
    typ = item.get("type")
    login = item.get("login") or {}
    rows: list[dict] = []
    edit = {"name": item.get("name") or "", "notes": item.get("notes") or "", "custom": []}
    if typ == 1:
        row(rows, "username", "Username", login.get("username"))
        row(rows, "password", "Password", login.get("password"), True)
        if login.get("totp"):
            row(rows, "totp", "Authenticator code", "present", True)
        uris = login.get("uris") or []
        for index, uri in enumerate(uris):
            if isinstance(uri, dict):
                row(rows, f"uri:{index}", "Website" if index == 0 else f"Website {index + 1}", uri.get("uri"))
        edit["username"] = login.get("username") or ""
        edit["url"] = (uris[0].get("uri") or "") if uris and isinstance(uris[0], dict) else ""
        edit["password"] = ""
    elif typ == 3:
        card = item.get("card") or {}
        for key, label in (("cardholderName", "Cardholder"), ("brand", "Brand"),
                           ("expMonth", "Expiry month"), ("expYear", "Expiry year")):
            row(rows, f"card:{key}", label, card.get(key))
        row(rows, "card:number", "Card number", card.get("number"), True)
        row(rows, "card:code", "Security code", card.get("code"), True)
    elif typ == 4:
        ident = item.get("identity") or {}
        for key in ("title", "firstName", "middleName", "lastName", "username", "company",
                    "email", "phone", "ssn", "passportNumber", "licenseNumber", "address1",
                    "address2", "city", "state", "postalCode", "country"):
            row(rows, "identity:" + key, key[0].upper() + key[1:], ident.get(key), key in ("ssn", "passportNumber", "licenseNumber"))
    for i, field in enumerate(item.get("fields") or []):
        if not isinstance(field, dict):
            continue
        field_type = field.get("type", 0)
        value = field.get("value") or ""
        row(rows, f"custom:{i}", field.get("name") or f"Field {i + 1}", value if value else ("present" if field_type == 1 else ""),
            field_type == 1, field_type == 3)
        edit["custom"].append({"index": i, "name": field.get("name") or "", "type": field_type,
                               "value": "" if field_type in (1, 3) else value})
    row(rows, "notes", "Notes", item.get("notes"))
    return {"id": item.get("id"), "name": item.get("name"), "type": typ, "revision": item.get("revisionDate"),
            "rows": rows, "edit": edit, "editable": typ in (1, 2, 3, 4),
            "canAutotype": typ == 1 and bool(login.get("username") or login.get("password"))}


def redact_list(directory: pathlib.Path) -> list:
    items = json.loads(cli(["list", "items"], directory, timeout=52))
    result = []
    for item in items:
        if not isinstance(item, dict) or not item.get("id") or not item.get("name"):
            continue
        login = item.get("login") or {}
        hints = []
        if login.get("username"):
            hints.append(login["username"])
        for entry in login.get("uris") or []:
            if isinstance(entry, dict) and entry.get("uri"):
                hints.append(entry["uri"])
                break
        if item.get("type") == 3:
            card = item.get("card") or {}
            hints.extend(str(card[k]) for k in ("brand", "cardholderName") if card.get(k))
        if item.get("type") == 4:
            identity = item.get("identity") or {}
            hints.extend(str(identity[k]) for k in ("email", "firstName", "lastName") if identity.get(k))
        # Never return note contents, passwords, TOTP secrets or hidden custom values.
        result.append({"id": item["id"], "name": item["name"], "type": item.get("type") or 0,
                       "subtitle": " · ".join(hints[:2]), "search": " ".join([item["name"], *hints])})
    result.sort(key=lambda entry: entry["name"].casefold())
    return result


def export_plaintext(directory: pathlib.Path, configured_path: str) -> dict:
    """Export the full vault as an atomic owner-only plaintext JSON file.

    Never put the vault/master password in argv, the reply, or stdout. A failed
    export leaves the prior export untouched. The setting is trusted user input.
    """
    if not isinstance(configured_path, str) or not configured_path.strip() or len(configured_path) > 4096:
        raise VaultError("Configure a valid export path")
    if any(ord(char) < 32 for char in configured_path):
        raise VaultError("Invalid export path")
    output = pathlib.Path(configured_path).expanduser()
    if not output.is_absolute():
        raise VaultError("Export path must be absolute or start with ~/")
    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # This requests a real Bitwarden export, not just cached item JSON.
    payload = cli(["export", "--format", "json", "--raw"], directory, timeout=52)
    try:
        doc = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise VaultError("Bitwarden returned an invalid export") from exc
    if not isinstance(doc, dict) or not isinstance(doc.get("items"), list):
        raise VaultError("Bitwarden returned an incomplete export")
    fd, name = tempfile.mkstemp(prefix=".bitwarden-export-", suffix=".tmp", dir=str(output.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, 0o600)
        os.replace(name, output)
    finally:
        if os.path.exists(name):
            os.unlink(name)
    return {"path": str(output)}


def generate_totp(seed: str, *, timestamp: int | None = None) -> str:
    """Standard RFC 6238 and Steam Guard TOTP from the unlocked in-RAM item.

    Generated only when requested, using the current clock; the secret is
    neither sent to a new process nor included in a command line.
    Unknown formats are rejected and callers may fall back to Bitwarden CLI.
    """
    if not isinstance(seed, str) or not seed.strip():
        raise VaultError("Invalid TOTP seed")
    seed = seed.strip()
    steam = seed.lower().startswith("steam://")
    period, digits, algorithm = 30, 5 if steam else 6, "sha1"
    if steam:
        secret = seed[len("steam://"):]
    elif seed.lower().startswith("otpauth://"):
        uri = urlsplit(seed)
        if uri.scheme.lower() != "otpauth" or uri.netloc.lower() != "totp":
            raise VaultError("Unsupported TOTP format")
        params = parse_qs(uri.query, keep_blank_values=True)
        secret = (params.get("secret") or [""])[0]
        algorithm = (params.get("algorithm") or ["sha1"])[0].lower().replace("-", "")
        try:
            period = int((params.get("period") or ["30"])[0])
            digits = int((params.get("digits") or ["6"])[0])
        except ValueError as exc:
            raise VaultError("Invalid TOTP parameters") from exc
    else:
        secret = seed
    if algorithm not in ("sha1", "sha256", "sha512") or not 1 <= digits <= 10 or not 1 <= period <= 86400:
        raise VaultError("Unsupported TOTP parameters")
    secret = "".join(secret.split()).rstrip("=").upper()
    if not secret or len(secret) > 4096:
        raise VaultError("Invalid TOTP seed")
    try:
        raw = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    except (ValueError, base64.binascii.Error) as exc:
        raise VaultError("Invalid TOTP seed") from exc
    if not raw:
        raise VaultError("Invalid TOTP seed")
    seconds = int(time.time() if timestamp is None else timestamp)
    digest = hmac.new(raw, (seconds // period).to_bytes(8, "big"), getattr(hashlib, algorithm)).digest()
    offset = digest[-1] & 0x0F
    binary = int.from_bytes(digest[offset:offset + 4], "big") & 0x7fffffff
    if steam:
        chars = "23456789BCDFGHJKMNPQRTVWXY"
        value = ""
        for _ in range(5):
            binary, index = divmod(binary, len(chars))
            value += chars[index]
        return value
    return str(binary % (10 ** digits)).zfill(digits)


def get_field(item: dict, selector: str) -> str:
    login = item.get("login") or {}
    if selector in ("username", "password"):
        value = login.get(selector)
    elif selector == "totp":
        raise VaultError("Use TOTP action")
    elif selector == "notes":
        value = item.get("notes")
    elif selector.startswith("uri:"):
        index = int(selector[4:])
        value = (login.get("uris") or [])[index].get("uri")
    elif selector.startswith("custom:"):
        index = int(selector[7:])
        field = (item.get("fields") or [])[index]
        if field.get("type") == 3:
            linked = {"100": login.get("username"), "101": login.get("password")}
            value = linked.get(str(field.get("value")))
        else:
            value = field.get("value")
    elif selector.startswith("card:"):
        value = (item.get("card") or {}).get(selector[5:])
    elif selector.startswith("identity:"):
        value = (item.get("identity") or {}).get(selector[9:])
    else:
        raise VaultError("Unknown field")
    if value is None or value == "":
        raise VaultError("Field empty")
    return str(value)


def autotype(directory: pathlib.Path, ident: str) -> dict:
    """Type into the previously focused Wayland app; never pass secrets via argv."""
    item = load_item(directory, ident)
    if item.get("type") != 1:
        raise VaultError("Only login entries support autotype")
    login = item.get("login") or {}
    username = login.get("username") or ""
    password = login.get("password") or ""
    if not username and not password:
        raise VaultError("No login fields to type")
    # Panel must have closed and compositor restored focus before typing.
    time.sleep(0.45)
    def type_text(value: str) -> None:
        if not value:
            return
        try:
            result = subprocess.run(["wtype", "-"], input=value, text=True,
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    timeout=15, check=False)
        except FileNotFoundError as exc:
            raise VaultError("wtype is not installed") from exc
        if result.returncode:
            raise VaultError("wtype failed")
    type_text(username)
    if username and password:
        subprocess.run(["wtype", "-k", "Tab"], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=5, check=True)
    type_text(password)
    return {"typed": True}


def patch_item(item: dict, changes: dict) -> dict:
    if not isinstance(changes, dict):
        raise VaultError("Invalid changes")
    allowed = {"name", "notes", "username", "password", "url", "custom"}
    if any(key not in allowed for key in changes):
        raise VaultError("Unsupported change")
    for key in ("name", "notes"):
        if key in changes:
            if not isinstance(changes[key], str):
                raise VaultError("Invalid field")
            if key == "name" and not changes[key].strip():
                raise VaultError("Name cannot be empty")
            item[key] = changes[key]
    if any(key in changes for key in ("username", "password", "url")):
        if item.get("type") != 1:
            raise VaultError("Only login items have these fields")
        login = item.setdefault("login", {})
        for key in ("username", "password"):
            if key in changes:
                if not isinstance(changes[key], str):
                    raise VaultError("Invalid field")
                login[key] = changes[key]
        if "url" in changes:
            if not isinstance(changes["url"], str):
                raise VaultError("Invalid URL")
            uris = login.setdefault("uris", [])
            if uris:
                uris[0]["uri"] = changes["url"]
            elif changes["url"]:
                uris.append({"uri": changes["url"], "match": None})
    for change in changes.get("custom", []):
        if not isinstance(change, dict) or not isinstance(change.get("index"), int):
            raise VaultError("Invalid custom field")
        fields = item.get("fields") or []
        ix = change["index"]
        if ix < 0 or ix >= len(fields):
            raise VaultError("Custom field changed elsewhere")
        current = fields[ix]
        if "name" in change:
            if not isinstance(change["name"], str):
                raise VaultError("Invalid field name")
            current["name"] = change["name"]
        if "value" in change:
            if current.get("type") == 3:
                raise VaultError("Linked field value cannot be edited here")
            if not isinstance(change["value"], str):
                raise VaultError("Invalid field value")
            current["value"] = change["value"]
    return item


def edit_item(directory: pathlib.Path, ident: str, payload: dict) -> dict:
    before = load_item(directory, ident)
    if payload.get("revision") != before.get("revisionDate"):
        raise VaultError("Item changed since opening; reload before saving")
    if before.get("organizationId") or before.get("edit") is False:
        # Organization items are allowed only if server permits: let bw decide
        pass
    after = patch_item(before, payload.get("changes"))
    encoded = base64.b64encode(json.dumps(after, ensure_ascii=False, separators=(",", ":")).encode()).decode()
    # Explicitly PIPE the encoded object. It must never appear in argv or shell history.
    cli(["edit", "item", item_id(ident)], directory, stdin=encoded + "\n", timeout=52)
    return {"id": ident, "name": after.get("name", "")}


def create_item(directory: pathlib.Path, payload: dict) -> dict:
    typ = payload.get("type", 1)
    if typ not in (1, 2):
        raise VaultError("Only login and secure note creation is supported")
    name = payload.get("name")
    if not isinstance(name, str) or not name.strip():
        raise VaultError("Name cannot be empty")
    notes = payload.get("notes") or ""
    if not isinstance(notes, str):
        raise VaultError("Invalid notes")
    item = {"type": typ, "name": name, "notes": notes, "favorite": False, "fields": [], "reprompt": 0}
    if typ == 1:
        login = {"username": payload.get("username") or "", "password": payload.get("password") or "",
                 "totp": None, "uris": []}
        if any(not isinstance(login[k], str) for k in ("username", "password")):
            raise VaultError("Invalid login field")
        url = payload.get("url") or ""
        if not isinstance(url, str):
            raise VaultError("Invalid URL")
        if url:
            login["uris"] = [{"uri": url, "match": None}]
        item["login"] = login
    else:
        item["secureNote"] = {"type": 0}
    encoded = base64.b64encode(json.dumps(item, ensure_ascii=False, separators=(",", ":")).encode()).decode()
    created = cli(["create", "item"], directory, stdin=encoded + "\n", timeout=52)
    try:
        output = json.loads(created)
    except json.JSONDecodeError:
        output = {}
    return {"id": output.get("id"), "name": name, "item": output}


def main(args: list[str]) -> object:
    if not args:
        raise VaultError("Missing command")
    op = args[0]
    directory = runtime_dir()
    if op in ("status", "expire"):
        was_expired = expire(directory)
        if op == "expire":
            return {"expired": was_expired}
        has_session = session_path(directory).exists()
        state = json.loads(cli(["status"], directory, session=has_session, timeout=15))
        actual = state.get("status", "locked")
        if has_session and actual != "unlocked":
            session_path(directory).unlink(missing_ok=True)
        try:
            # The previous plugin spawned an unauthenticated bw serve on this port.
            with socket.create_connection(("127.0.0.1", 8087), timeout=0.05):
                old_port_listening = True
        except OSError:
            old_port_listening = False
        return {"status": actual if has_session else ("unauthenticated" if actual == "unauthenticated" else "locked"),
                "email": state.get("userEmail") or "", "expired": was_expired,
                "legacyPort": old_port_listening, "runtime": str(directory)}
    if op == "unlock":
        config_path = directory / "unlock.cmd"
        command = consume(config_path).strip()
        if not command:
            raise VaultError("Decrypt command not configured")
        try:
            decrypted = subprocess.run(["/bin/sh", "-c", command], capture_output=True,
                                       text=True, timeout=40, check=False)
        except subprocess.TimeoutExpired as exc:
            raise VaultError("Security-key command timed out") from exc
        if decrypted.returncode:
            raise VaultError("Security-key command failed or was cancelled")
        password = decrypted.stdout.rstrip("\r\n")
        if not password:
            raise VaultError("Security-key command returned no password")
        # passwordfile reads stdin; no master password or session in argv.
        key = cli(["unlock", "--passwordfile", "/dev/stdin", "--raw"], directory,
                  stdin=password + "\n", session=False, timeout=17).strip()
        if not key or " " in key or "\n" in key:
            raise VaultError("Bitwarden did not return a session")
        private_replace(session_path(directory), key)
        # Do not block hardware-key unlock on a potentially slow network sync.
        # The user can request a sync explicitly from the panel.
        return {"status": "unlocked"}
    if op == "lock":
        try:
            if session_path(directory).exists():
                cli(["lock"], directory, timeout=15)
        finally:
            session_path(directory).unlink(missing_ok=True)
        return {"status": "locked"}
    require_unlocked(directory)
    if op == "list":
        response = redact_list(directory)
    elif op == "detail":
        response = describe(load_item(directory, args[1]))
    elif op == "autotype":
        response = autotype(directory, args[1])
    elif op == "copy":
        selector = args[2]
        if selector == "totp":
            response = {"value": cli(["get", "totp", item_id(args[1])], directory).strip()}
        else:
            response = {"value": get_field(load_item(directory, args[1]), selector)}
    elif op == "edit":
        response = edit_item(directory, args[1], json.loads(consume(directory / "request.json")))
    elif op == "create":
        response = create_item(directory, json.loads(consume(directory / "request.json")))
    elif op == "export":
        response = export_plaintext(directory, args[1])
    elif op == "sync":
        cli(["sync"], directory, timeout=52)
        response = {"synced": True}
    elif op == "generate":
        if len(args) > 1 and args[1] == "passphrase":
            cmd = ["generate", "--passphrase", "--words", "6", "--separator", "-"]
        else:
            cmd = ["generate", "--length", "20", "--uppercase", "--lowercase", "--number", "--special"]
        response = {"value": cli(cmd, directory).strip()}
    else:
        raise VaultError("Unknown operation")
    touch(directory)
    return response


if __name__ == "__main__":
    try:
        print(json.dumps({"ok": True, "data": main(sys.argv[1:])}, ensure_ascii=False))
    except (VaultError, json.JSONDecodeError, IndexError, KeyError, ValueError, OSError) as exc:
        print(json.dumps({"ok": False, "error": str(exc) if isinstance(exc, VaultError) else "Invalid request"}))
