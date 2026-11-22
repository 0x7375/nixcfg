# Bitwarden for Noctalia (v2.7)

Keyboard-oriented vault search, item viewing and editing. Requires Noctalia 5.4+ (plugin API 43), `bitwarden-cli`, Python 3, `xdg-open`, and `wtype` for autotype. Uses your existing `decrypt_cmd` security-key command; it does **not** implement native WebAuthn PRF. No `bw serve` or listening TCP port.

## Install / open

Replace the **entire** old `bitwarden/` directory with this directory and reload the plugin/Noctalia. Existing `decrypt_cmd` settings are preserved. Log into the Bitwarden CLI once (`bw login`); the plugin can then unlock a *locked* session.

**Recommended shortcut** to unlock *before* the panel appears:

```sh
noctalia msg plugin me/bitwarden:service all toggle_menu
```

This requests the existing key-based unlock (if needed), loads the vault and opens the populated panel after the key prompt has completed. A second press when the panel is already open closes it immediately. Direct `noctalia msg panel-toggle me/bitwarden:vault` is also supported, but must briefly instantiate/close the panel to defer unlocking to the service.

## Behavior

- On a cold start, the system's security-key prompt is shown before the panel; after success, search opens automatically with its first result selected. A warm session opens from cached metadata without an intermediate loading view.
- Search, selected result, open item, selected field and in-progress editor stay in **this plugin's memory** when the panel closes. They reset on a fresh unlock or explicit Lock. No plaintext vault data is saved to persistent plugin settings.
- The panel is fixed-height, but each active view and its scrollable region grow to fill the available space; the editor buttons remain pinned at the bottom. Search and list rows keep stable widths, and item fields start immediately beneath the header. View-specific keys prevent scroll layout state from leaking between search, detail, and editor on re-open. Editor inputs are narrower than their scroll area so the scrollbar has a dedicated gutter. No help footer, `Login` label or creation buttons.
- Enter once opens the selected search result; Enter on a detail field copies it except **Website**, which launches `xdg-open` with the URL and closes the panel. Only HTTP(S) destinations are supported.
- Ctrl+O edits the current item; Ctrl+S saves it. Ctrl+E is reserved for the native input end-of-line shortcut if `shell.readline_shortcuts` is enabled. Edits return directly to the detail view after the server operation, without a full vault list reload. Ctrl+T autotypes into the previously focused application.
- Ctrl+N / Ctrl+P or the configured Noctalia Up/Down shortcuts move through results and fields. In the editor they move input focus forward/back. The plugin reads effective `keybinds.up`, `down`, `tab_next`, `tab_previous`, `validate` and `save` settings, but **Noctalia requires a fixed `capture_keys` set in the manifest**: alternate chords not listed there still need adding to `plugin.toml`. Tab / Shift+Tab remain native.
- Held navigation keys repeat after ~340 ms at ~65 ms per step via `onFrameTick` (on plugin API 43, before native repeat arrives in 57).
- The manifest uses fixed panel-wide key capture. Ctrl+O avoids intercepting the native Ctrl+E readline binding. If Ctrl+E does not move to end of line, turn on `shell.readline_shortcuts` in Noctalia’s Shell settings.
- Alt+H goes Back / cancels editing. Ctrl+H and Backspace are **not** captured, to leave normal input editing to Noctalia. Noctalia's documented readline shortcuts do **not** include Ctrl+H as an alias for Backspace; whether it acts as Backspace depends on the host version. The plugin API cannot safely emulate an in-input Backspace with correct cursor/selection handling. Escape is reserved by Noctalia and closes the panel, including during editing.
- In item details, hidden fields have an eye button that reveals/hides their contents without copying them. Space also reveals/hides the selected secret field (including current TOTP); a focused search/editor input keeps typing spaces normally. Revealed text is only stored in the panel VM; it remains revealed until manually hidden, until leaving item details, or until the panel closes. Revealed TOTP codes refresh at their standard 30-second boundary without hiding.
- Hidden values appear as eight bullets. Standard authenticator codes are generated from the cached in-memory secret, rather than launching `bw get totp`; unusual/unsupported formats still use the official CLI as a fallback.
- Website icons are available as an **opt-in** `website_icons = true` plugin setting. Fetching a site icon sends its hostname to the official Bitwarden icon service/CDN. Icons are downloaded asynchronously into an ephemeral private runtime cache and Noctalia reads them as local PNG files. Other entries use the generic local glyphs. No websites are contacted while the setting is false.
- Creation was removed from the UI until password and address-generation workflows are supported. The internal CLI create capability remains in the backend, unused by this UI.

## Security

The backend uses a private 0600 Unix socket under a 0700 XDG runtime directory and caches decrypted vault items in the daemon's RAM while the 15-minute session is valid. It checks connecting client UIDs with Linux `SO_PEERCRED` and puts no passwords in argv. It passes Bitwarden edits to `bw edit` via stdin. Same-user processes are not a security isolation boundary; compromised processes under your user could access the cache or session. The UI receives redacted metadata; visible detail values are returned as needed. Clipboard contents are cleared after ~30 seconds if unchanged; independent clipboard managers may retain history.

The service unlocks before opening the panel. Unlock command text is written only in the private runtime directory and consumed by the backend; the decrypted master password passes to `bw unlock --passwordfile /dev/stdin`. Do not configure `decrypt_cmd` to print secrets to logs. `xdg-open` receives HTTP(S) URLs as an argument array (no shell interpolation).

## Runtime files and tests

The `tests/` directory is used only for development and does not need to be
installed. If packaging through Nix, you may exclude `tests/` from the plugin
source/install path. Runtime needs `panel.luau`, `service.luau`, `plugin.toml`,
`backend.py`, `client.py`, `daemon.py`, `icons.py`, and `translations/en.json`.

## Testing

```sh
python3 -m unittest discover -s bitwarden/tests -p 'test_ui_contract.py' -v
python3 -m unittest discover -s bitwarden/tests -v
```

Python-side tests use a fake Bitwarden CLI. **The Luau UI cannot be executed here without a running Noctalia instance.** Verify the layout on first open and after state restoration (especially long custom-field edits), focus, key holds, website launching and unlock transition in Noctalia after installing. The fake-CLI backend suite may hang intermittently in some environments; a timeout is not a test pass.
