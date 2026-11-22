--!nonstrict
-- Clipboard expiry, idle vault expiry, and unlock-before-panel routing.
-- The service never publishes any decrypted vault contents; only redacted
-- search metadata and a session epoch are shared with the panel.
noctalia.setUpdateInterval(1000)

local backend = (noctalia.pluginDir() or "") .. "/client.py"
local tick = 0
local pendingClipboard = nil
local expireInFlight = false
local opening = false
local epoch = tonumber(noctalia.state.get("vault_epoch")) or 0

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

local function openPanelAfterUnlock()
  if noctalia.state.get("panel_visible") == true then
    noctalia.togglePanel("me/bitwarden:vault")
    return
  end
  if opening then return end
  opening = true
  local launched = helper({ "prepare" }, function(prepared, errorText)
    if errorText or type(prepared) ~= "table" or type(prepared.runtime) ~= "string" then
      opening = false
      noctalia.notifyError("Bitwarden", errorText or "Private runtime is unavailable")
      return
    end
    noctalia.state.set("vault_runtime", prepared.runtime)
    local command = noctalia.getConfig("decrypt_cmd")
    if type(command) ~= "string" or command == "" then
      opening = false
      noctalia.notifyError("Bitwarden", "Configure decrypt_cmd in plugin settings")
      return
    end
    -- If already unlocked, the daemon will discard this private command file.
    -- On a cold start, bw unlock consumes it via stdin, never command arguments.
    if not noctalia.writeFile(prepared.runtime .. "/unlock.cmd", command) then
      opening = false
      noctalia.notifyError("Bitwarden", "Unable to prepare unlock command")
      return
    end
    local started = helper({ "open" }, function(data, failed)
      opening = false
      if failed then
        noctalia.notifyError("Bitwarden", failed)
        return
      end
      if type(data) ~= "table" or data.status ~= "unlocked" then
        noctalia.notifyError("Bitwarden", if data and data.status == "unauthenticated" then "Log in to the Bitwarden CLI first" else "Vault is locked")
        return
      end
      if noctalia.state.get("vault_ready") ~= true then
        epoch += 1
        noctalia.state.set("vault_epoch", epoch)
      end
      noctalia.state.set("vault_initial_items", data.items or {})
      noctalia.state.set("vault_ready", true)
      -- The panel only appears after the security-key dialog and initial load.
      noctalia.togglePanel("me/bitwarden:vault")
    end)
    if not started then
      opening = false
      noctalia.notifyError("Bitwarden", "Could not start unlock")
    end
  end, 10000)
  if not launched then
    opening = false
    noctalia.notifyError("Bitwarden", "Could not prepare vault")
  end
end

noctalia.state.watch("unlock_request", function(_request)
  openPanelAfterUnlock()
end)

noctalia.state.watch("clipboard_request", function(request)
  if type(request) ~= "table" or type(request.value) ~= "string" or request.value == "" then return end
  pendingClipboard = { value = request.value, remaining = 30 }
  noctalia.state.set("clipboard_request", { value = "" })
end)

function onIpc(event, _payload)
  if event == "toggle_menu" or event == "open" then
    openPanelAfterUnlock()
  end
end

function update()
  tick += 1
  if pendingClipboard ~= nil then
    pendingClipboard.remaining -= 1
    if pendingClipboard.remaining <= 0 then
      if noctalia.clipboardText() == pendingClipboard.value then
        noctalia.copyToClipboard("", "text/plain;charset=utf-8")
        noctalia.runAsync({ "noctalia", "msg", "clipboard-clear" })
      end
      pendingClipboard = nil
    end
  end
  if tick == 1 or tick % 30 == 0 then
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
