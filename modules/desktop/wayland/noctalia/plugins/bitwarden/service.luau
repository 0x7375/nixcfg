--!nonstrict
-- Clipboard expiry, idle vault expiry, and prompt-first unlock routing.
-- The service never publishes any decrypted vault contents; only redacted
-- search metadata and a session epoch are shared with the panel.
noctalia.setUpdateInterval(200)

local backend = (noctalia.pluginDir() or "") .. "/client.py"
local lastExpireCheck = 0
local unlockRuntime = ""
local loadingPanelOpened = false
local pendingClipboard = nil
local expireInFlight = false
local opening = false
local epoch = tonumber(noctalia.state.get("vault_epoch")) or 0
-- Shared plugin state survives a service reload. A pending unlock from an old
-- service instance cannot complete, so never retain its stale loading flag.
if noctalia.state.get("vault_loading") == true then
  noctalia.state.set("vault_loading", false)
end
noctalia.state.set("vault_show_loading", false)

local function helper(args, done, timeoutMs)
  local argv = { "python3", backend }
  for _, arg in ipairs(args) do table.insert(argv, arg) end
  return noctalia.runAsync(argv, function(result)
    if result.exitCode ~= 0 or result.timedOut or result.stdoutTruncated then
      done(nil, "Bitwarden helper failed")
      return
    end
    local response = noctalia.json.decode(result.stdout or "")
    if type(response) ~= "table" or response.ok ~= true then
      done(nil, if type(response) == "table" then response.error or "Bitwarden operation failed" else "Invalid Bitwarden response")
      return
    end
    done(response.data, nil)
  end, timeoutMs or 60000)
end

local function ensurePanelOpen()
  -- togglePanel is not an idempotent 'show': never call it on a visible panel.
  -- The external security-key prompt may have closed the panel, so check
  -- actual onOpen/onClose state, not whether we previously toggled it.
  if noctalia.state.get("panel_visible") ~= true then
    noctalia.togglePanel("me/bitwarden:vault")
  end
end

local function unlockFailed(reason)
  opening = false
  loadingPanelOpened = false
  if unlockRuntime ~= "" then
    noctalia.removeFile(unlockRuntime .. "/unlock.stage")
  end
  unlockRuntime = ""
  local explanation = reason or "Bitwarden unlock failed"
  noctalia.state.set("vault_error", explanation)
  noctalia.state.set("vault_show_loading", false)
  noctalia.state.set("vault_loading", false)
  noctalia.notifyError("Bitwarden", explanation)
end

local function openPanelAfterUnlock()
  if opening then return end
  if noctalia.state.get("vault_ready") == true then
    -- A warm vault remains instant, with normal open/close toggle semantics.
    noctalia.togglePanel("me/bitwarden:vault")
    return
  end

  opening = true
  loadingPanelOpened = false
  unlockRuntime = ""
  noctalia.state.set("vault_error", "")
  noctalia.state.set("vault_loading_stage", "Loading vault")
  noctalia.state.set("vault_loading", true)
  noctalia.state.set("vault_show_loading", false)
  -- Do NOT open the panel here. The key's own prompt comes first.
  local launched = helper({ "prepare" }, function(prepared, errorText)
    if errorText or type(prepared) ~= "table" or type(prepared.runtime) ~= "string" then
      unlockFailed(errorText or "Private runtime is unavailable")
      return
    end
    unlockRuntime = prepared.runtime
    noctalia.state.set("vault_runtime", unlockRuntime)
    local command = noctalia.getConfig("decrypt_cmd")
    if type(command) ~= "string" or command == "" then
      unlockFailed("Configure decrypt_cmd in plugin settings")
      return
    end
    -- Clear any marker left by an interrupted previous process. The daemon
    -- writes a fresh stage marker only AFTER the key prompt has completed.
    noctalia.removeFile(unlockRuntime .. "/unlock.stage")
    if not noctalia.writeFile(unlockRuntime .. "/unlock.cmd", command) then
      unlockFailed("Unable to prepare unlock command")
      return
    end
    local started = helper({ "open" }, function(data, failed)
      if failed then
        unlockFailed(failed)
        return
      end
      if type(data) ~= "table" or data.status ~= "unlocked" then
        unlockFailed(if data and data.status == "unauthenticated" then "Log in to the Bitwarden CLI first" else "Vault is locked")
        return
      end
      opening = false
      unlockRuntime = ""
      if noctalia.state.get("vault_ready") ~= true then
        epoch += 1
        noctalia.state.set("vault_epoch", epoch)
      end
      noctalia.state.set("vault_initial_items", data.items or {})
      noctalia.state.set("vault_opened_at", noctalia.nowMs())
      -- Set the cache first. Both an already-visible spinner and a newly
      -- opened panel then transition directly to the populated search view.
      noctalia.state.set("vault_ready", true)
      noctalia.state.set("vault_show_loading", false)
      noctalia.state.set("vault_loading", false)
      noctalia.state.set("vault_loading_stage", "")
      ensurePanelOpen()
    end)
    if not started then
      unlockFailed("Could not start unlock")
    end
  end, 10000)
  if not launched then
    unlockFailed("Could not prepare vault")
  end
end

noctalia.state.watch("unlock_request", function(_request)
  openPanelAfterUnlock()
end)

noctalia.state.watch("clipboard_request", function(request)
  if type(request) ~= "table" or type(request.value) ~= "string" or request.value == "" then return end
  pendingClipboard = { value = request.value, expiresAt = noctalia.nowMs() + 30000 }
  noctalia.state.set("clipboard_request", { value = "" })
end)

function onIpc(event, _payload)
  if event == "toggle_menu" or event == "open" then
    openPanelAfterUnlock()
  end
end

function update()
  local now = noctalia.nowMs()
  -- The daemon creates this marker as soon as decrypt_cmd (the external
  -- security-key prompt) returns, BEFORE running bw unlock / bw list items.
  -- Poll only while unlocking; the file contains no secret.
  if opening and not loadingPanelOpened and unlockRuntime ~= ""
    and noctalia.fileExists(unlockRuntime .. "/unlock.stage") then
    loadingPanelOpened = true
    noctalia.state.set("vault_show_loading", true)
    ensurePanelOpen()
  end
  if pendingClipboard ~= nil and now >= pendingClipboard.expiresAt then
    if noctalia.clipboardText() == pendingClipboard.value then
      noctalia.copyToClipboard("", "text/plain;charset=utf-8")
      noctalia.runAsync({ "noctalia", "msg", "clipboard-clear" })
    end
    pendingClipboard = nil
  end
  if lastExpireCheck == 0 or now - lastExpireCheck >= 30000 then
    lastExpireCheck = now
    if not expireInFlight then
      expireInFlight = true
      local launched = helper({ "expire" }, function(data, _error)
        expireInFlight = false
        if type(data) == "table" and data.expired == true then
          noctalia.state.set("vault_ready", false)
          noctalia.state.set("vault_initial_items", {})
        end
      end, 25000)
      if not launched then expireInFlight = false end
    end
  end
end

function onExit(_signal, reason)
  pendingClipboard = nil
  if reason == "disable" or reason == "uninstall" or reason == "shutdown" then
    noctalia.runAsync({ "python3", backend, "lock" })
  end
end
