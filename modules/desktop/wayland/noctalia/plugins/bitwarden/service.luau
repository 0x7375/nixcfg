--!nonstrict
-- Bitwarden service
-- Handles bw serve, status poll, unlock/sync/lock/copy/export/autotype.

noctalia.setUpdateInterval(500)

-- Hardcoded Configuration
local SERVE_PORT = 8087
local VAULT_TIMEOUT_MINUTES = 15
local AUTO_SERVE = true
local CLEAR_CLIPBOARD_SECONDS = 30
local AUTOTYPE_DELAY_SECONDS = 0.35

local STATUS_TICKS = 4 -- 4 * 500ms = 2s between status polls when serve is up
local SLOW_POLL_TICKS = 60 -- 30s when serve is down or user is logged out
local SERVE_START_COOLDOWN_TICKS = 10

local tickCount = 0
local serveStartCooldown = 0
local nextSlowPollTick = 0
local statusInFlight = false
local opInFlight = false
local syncInFlight = false
local itemsRevision = noctalia.state.get("items_revision") or 0
local lastStatusKey = ""
local pendingClear = nil
local weStartedServe = false
local sessionUnlocked = false
local unlockDeadlineTick = nil
local pendingQuietLock = false
local resumeName = nil

local status = {
  vault = "offline",
  email = "",
  serverUrl = "",
  serveUp = false,
  bwAvailable = false,
  error = "",
}

local function touchUnlockActivity()
  unlockDeadlineTick = tickCount + VAULT_TIMEOUT_MINUTES * 120
end

local function clearUnlockTimer()
  unlockDeadlineTick = nil
  sessionUnlocked = false
end

local function log(msg)
  noctalia.log(`bitwarden: {msg}`)
end

local function baseUrl()
  return `http://127.0.0.1:{SERVE_PORT}`
end

local function publishStatus()
  local key = `{status.vault}|{status.email}|{if status.serveUp then "1" else "0"}|{status.error}`
  if key == lastStatusKey then return end
  lastStatusKey = key
  noctalia.state.set("status", {
    vault = status.vault,
    email = status.email,
    serverUrl = status.serverUrl,
    serveUp = status.serveUp,
    bwAvailable = status.bwAvailable,
    error = status.error,
  })
end

local function setStatus(patch)
  for k, v in pairs(patch) do
    status[k] = v
  end
  publishStatus()
end

local function parseBwResponse(body)
  if type(body) ~= "string" or body == "" then return nil, "empty response" end
  local decoded = noctalia.json.decode(body)
  if type(decoded) ~= "table" then return nil, "invalid JSON" end
  if decoded.success == false then
    local msg = decoded.message
    if type(msg) ~= "string" or msg == "" then msg = "request failed" end
    return nil, msg
  end
  return decoded.data, nil
end

local function httpJson(method, path, body, onDone)
  local headers = { "Accept: application/json" }
  if body ~= nil then table.insert(headers, "Content-Type: application/json") end
  noctalia.http({
    method = method,
    url = baseUrl() .. path,
    headers = headers,
    body = body,
  }, function(res)
    if not res.ok then
      onDone(nil, "serve unreachable")
      return
    end
    local data, err = parseBwResponse(res.body)
    if err ~= nil then
      onDone(nil, err)
      return
    end
    onDone(data, nil)
  end)
end

local function applyStatusPayload(data)
  if type(data) ~= "table" then
    setStatus({ serveUp = true, vault = "locked", error = "" })
    return
  end
  local payload = data
  if type(data.template) == "table" then
    payload = data.template
  elseif type(data.data) == "table" and type(data.data.status) == "string" then
    payload = data.data
  end
  local vault = payload.status
  if type(vault) ~= "string" or vault == "" then
    vault = "locked"
  end
  setStatus({
    serveUp = true,
    vault = vault,
    email = if type(payload.userEmail) == "string" then payload.userEmail else "",
    serverUrl = if type(payload.serverUrl) == "string" then payload.serverUrl else "",
    error = "",
  })
  if vault == "unlocked" then
    if not sessionUnlocked then
      pendingQuietLock = true
    elseif unlockDeadlineTick == nil then
      touchUnlockActivity()
    end
  else
    unlockDeadlineTick = nil
  end
end

local function startServe()
  if not status.bwAvailable or serveStartCooldown > 0 then return end
  serveStartCooldown = SERVE_START_COOLDOWN_TICKS
  local cmd = `bw serve --hostname 127.0.0.1 --port {SERVE_PORT} >/dev/null 2>&1 &`
  log(`starting serve on 127.0.0.1:{SERVE_PORT}`)
  weStartedServe = true
  noctalia.runAsync(cmd)
end

local function ensureServe(forceStart)
  if forceStart or AUTO_SERVE then
    startServe()
  end
end

local function shellQuote(s)
  return "'" .. string.gsub(tostring(s), "'", "'\\''") .. "'"
end

local function applyCliStatusResult(result, serveErr)
  local vault = "offline"
  if type(result) == "table" and result.exitCode == 0 then
    local decoded = noctalia.json.decode(result.stdout or "")
    if type(decoded) == "table" and type(decoded.status) == "string" and decoded.status ~= "" then
      if decoded.status == "unauthenticated" then
        vault = "unauthenticated"
      elseif decoded.status == "locked" or decoded.status == "unlocked" then
        vault = "offline"
      else
        vault = decoded.status
      end
    end
  end
  setStatus({ serveUp = false, vault = vault, email = "", serverUrl = "", error = serveErr or "" })
  if vault == "unauthenticated" then
    nextSlowPollTick = tickCount + SLOW_POLL_TICKS
  elseif vault == "offline" and AUTO_SERVE then
    ensureServe(false)
  end
end

local function pollCliStatus(serveErr)
  noctalia.runAsync("bw status", function(result)
    statusInFlight = false
    if syncInFlight then return end
    applyCliStatusResult(result, serveErr)
  end, 10000)
end

local function pollStatus()
  if statusInFlight or syncInFlight then return end
  if not status.bwAvailable then
    setStatus({ serveUp = false, vault = "offline", error = "bw not found" })
    return
  end
  if status.vault == "unauthenticated" then
    if tickCount < nextSlowPollTick then return end
    nextSlowPollTick = tickCount + SLOW_POLL_TICKS
    statusInFlight = true
    pollCliStatus("")
    return
  end
  if not status.serveUp and tickCount < nextSlowPollTick then return end

  statusInFlight = true
  httpJson("GET", "/status", nil, function(data, err)
    if syncInFlight then
      statusInFlight = false
      return
    end
    if err ~= nil then
      nextSlowPollTick = tickCount + SLOW_POLL_TICKS
      pollCliStatus(err)
      return
    end
    statusInFlight = false
    nextSlowPollTick = 0
    applyStatusPayload(data)
  end)
end

local function stopServe(onDone)
  local cmd = table.concat({
    `fuser -k {SERVE_PORT}/tcp >/dev/null 2>&1 || true`,
    `pkill -f 'bw\\.js serve' >/dev/null 2>&1 || true`,
    `pkill -f 'bw serve' >/dev/null 2>&1 || true`,
  }, "; ")
  log(`stopping serve (port {SERVE_PORT})`)
  noctalia.runAsync(cmd, function()
    if onDone ~= nil then onDone() end
  end, 5000)
end

local function scheduleClipboardClear(text)
  if CLEAR_CLIPBOARD_SECONDS <= 0 then
    pendingClear = nil
    return
  end
  pendingClear = { text = text, ticksLeft = math.max(1, math.floor(CLEAR_CLIPBOARD_SECONDS * 2)) }
end

local function copySecret(value)
  if type(value) ~= "string" or value == "" then return false end
  noctalia.copyToClipboard(value, "text/plain;charset=utf-8")
  scheduleClipboardClear(value)
  return true
end

local function parseSecretValue(data)
  if type(data) == "string" and data ~= "" then return data end
  if type(data) ~= "table" then return nil end
  if type(data.data) == "string" and data.data ~= "" then return data.data end
  if type(data.data) == "table" and type(data.data.data) == "string" and data.data.data ~= "" then return data.data.data end
  return nil
end

local function doGenerate(mode)
  if opInFlight then return end
  if not status.bwAvailable then
    noctalia.notifyError("Bitwarden", "bw CLI missing")
    return
  end
  local passphrase = (mode == "passphrase")
  opInFlight = true

  local function finish(value, err)
    opInFlight = false
    if err ~= nil or type(value) ~= "string" or value == "" then
      noctalia.notifyError("Bitwarden", err or "Generate failed")
      return
    end
    copySecret(value)
  end

  local query = ""
  if passphrase then
    query = "passphrase=true&words=6&separator=-"
  else
    query = "length=20&uppercase=true&lowercase=true&number=true"
  end

  if not status.serveUp then ensureServe(true) end
  httpJson("GET", `/generate?{query}`, nil, function(data, err)
    if err ~= nil then
      finish(nil, "Serve API generation failed")
      return
    end
    local value = parseSecretValue(data)
    if value == nil then
      finish(nil, "Failed to parse generation")
      return
    end
    finish(value, nil)
  end)
end

local function extractField(item, field)
  if type(item) ~= "table" then return nil end
  local login = item.login
  
  if field:sub(1, 7) == "custom:" then
    local customName = field:sub(8)
    if type(item.fields) == "table" then
      for _, f in ipairs(item.fields) do
        if type(f) == "table" and f.name == customName then
          return tostring(f.value)
        end
      end
    end
    return nil
  elseif field == "password" then
    if type(login) == "table" and type(login.password) == "string" then return login.password end
    if type(item.notes) == "string" and item.notes ~= "" then return item.notes end
    return nil
  elseif field == "username" then
    if type(login) == "table" and type(login.username) == "string" then return login.username end
  elseif field == "totp" then
    if type(login) == "table" and type(login.totp) == "string" then return login.totp end
  elseif field == "uri" then
    if type(login) == "table" and type(login.uris) == "table" then
      for _, u in login.uris do
        if type(u) == "table" and type(u.uri) == "string" and u.uri ~= "" then return u.uri end
      end
    end
  end
  return nil
end

local function copyItemField(itemId, field, itemName)
  if type(itemId) ~= "string" or itemId == "" then return end
  if status.vault ~= "unlocked" then
    noctalia.notifyError("Bitwarden", "Vault Locked")
    return
  end
  if type(field) ~= "string" or field == "" then field = "password" end

  local isCustom = field:sub(1, 7) == "custom:"

  local function fetchFullItem()
    httpJson("GET", `/object/item/{noctalia.string.urlEncode(itemId)}`, nil, function(itemData, itemErr)
      if itemErr ~= nil then
        noctalia.notifyError("Bitwarden", itemErr)
        return
      end
      local item = itemData
      if type(itemData) == "table" and type(itemData.data) == "table" and itemData.id == nil then
        item = itemData.data
      end
      local value = extractField(item, field)
      if value == nil or value == "" then
        noctalia.notifyError("Bitwarden", "Field empty")
        return
      end
      touchUnlockActivity()
      if copySecret(value) and type(itemName) == "string" and itemName ~= "" then
        resumeName = itemName
      end
    end)
  end

  if isCustom then
    fetchFullItem()
  else
    local path = `/object/{field}/{noctalia.string.urlEncode(itemId)}`
    httpJson("GET", path, nil, function(data, err)
      local value = if err == nil then parseSecretValue(data) else nil
      if value ~= nil then
        touchUnlockActivity()
        if copySecret(value) and type(itemName) == "string" and itemName ~= "" then
          resumeName = itemName
        end
        return
      end
      fetchFullItem()
    end)
  end
end

local function autotypeCmd(username, password)
  local steps = {}
  if username ~= "" then
    table.insert(steps, "wtype -- " .. shellQuote(username))
    table.insert(steps, "wtype -k Tab")
  end
  table.insert(steps, "wtype -- " .. shellQuote(password))
  return table.concat(steps, " && ")
end

local function doAutotype(itemId)
  if type(itemId) ~= "string" or itemId == "" then return end
  if status.vault ~= "unlocked" then
    noctalia.notifyError("Bitwarden", "Vault Locked")
    return
  end
  if opInFlight then return end
  opInFlight = true

  httpJson("GET", `/object/item/{noctalia.string.urlEncode(itemId)}`, nil, function(itemData, itemErr)
    opInFlight = false
    if itemErr ~= nil then
      noctalia.notifyError("Bitwarden", itemErr)
      return
    end
    local item = itemData
    if type(itemData) == "table" and type(itemData.data) == "table" and itemData.id == nil then
      item = itemData.data
    end
    local username = extractField(item, "username") or ""
    local password = extractField(item, "password") or ""
    if password == "" then
      noctalia.notifyError("Bitwarden", "Field empty")
      return
    end
    touchUnlockActivity()
    local cmd = `sleep {AUTOTYPE_DELAY_SECONDS} && {autotypeCmd(username, password)}`
    noctalia.runAsync(cmd, function(result)
      if type(result) == "table" and result.exitCode ~= 0 then
        noctalia.notifyError("Bitwarden", "Autotype failed (is wtype installed?)")
      end
    end, 10000)
  end)
end

local function curlPost(path, onDone)
  local cmd = `curl -sS -m 15 -X POST http://127.0.0.1:{SERVE_PORT}{path} -H 'Accept: application/json'`
  noctalia.runAsync(cmd, function(result)
    if type(result) ~= "table" then return onDone(false, "no result") end
    if result.timedOut then return onDone(false, "timed out") end
    if result.exitCode ~= 0 then return onDone(false, if result.stderr ~= "" then result.stderr else "curl failed") end
    local data, err = parseBwResponse(result.stdout)
    if err ~= nil then return onDone(false, err) end
    onDone(true, nil)
  end, 20000)
end

local function openVaultLauncher(toggle)
  local query = "/bw "
  if resumeName ~= nil then
    query ..= resumeName .. " "
    resumeName = nil
  end
  local command = if toggle then "panel-toggle" else "panel-open"
  noctalia.runAsync(`noctalia msg {command} launcher {shellQuote(query)}`)
end

local function markItemsChanged()
  itemsRevision += 1
  noctalia.state.set("items_revision", itemsRevision)
end

local function syncVault(openLauncher, notifySuccess)
  if opInFlight then return end
  opInFlight = true
  syncInFlight = true
  -- Do not expose cached entries while refreshing them.
  setStatus({ vault = "syncing", error = "" })
  curlPost("/sync", function(ok, err)
    syncInFlight = false
    opInFlight = false
    if ok then
      markItemsChanged()
      if notifySuccess then noctalia.notify("Bitwarden", "Vault Synced") end
    else
      noctalia.notifyError("Bitwarden", "Sync failed; showing local vault: " .. (err or "unknown error"))
    end
    if sessionUnlocked then touchUnlockActivity() end
    setStatus({ serveUp = true, vault = "unlocked", error = if ok then "" else (err or "Sync failed") })
    pollStatus()
    if openLauncher then
      noctalia.notify("Bitwarden", "Vault Unlocked")
      openVaultLauncher(false)
    end
  end)
end

local function doUnlockCmd(openLauncher)
  if opInFlight then return end

  local cmd = noctalia.getConfig("decrypt_cmd")
  if type(cmd) ~= "string" or cmd == "" then
    noctalia.notifyError("Bitwarden", "Decrypt command not configured in settings")
    return
  end

  opInFlight = true

  noctalia.runAsync(cmd, function(result)
    if type(result) ~= "table" or result.exitCode ~= 0 then
      opInFlight = false
      return
    end

    local password = noctalia.string.trim(result.stdout or "")
    local body = noctalia.json.encode({ password = password })

    if body == nil then
      opInFlight = false
      return
    end

    httpJson("POST", "/unlock", body, function(_data, err)
      opInFlight = false
      if err ~= nil then
        noctalia.notifyError("Bitwarden", err)
        setStatus({ error = err })
        return
      end
      resumeName = nil
      sessionUnlocked = true
      pendingQuietLock = false
      touchUnlockActivity()
      syncVault(openLauncher, false)
    end)
  end, 30000)
end

local function doLock(quiet)
  if opInFlight then return end
  opInFlight = true
  curlPost("/lock", function(ok, err)
    opInFlight = false
    clearUnlockTimer()
    if not ok then
      if not quiet then noctalia.notifyError("Bitwarden", err or "Lock failed") end
      pollStatus()
      return
    end
    resumeName = nil
    setStatus({ serveUp = true, vault = "locked", error = "" })
    if not quiet then noctalia.notify("Bitwarden", "Vault Locked") end
  end)
end

local function doSync()
  if status.vault ~= "unlocked" then return end
  syncVault(false, true)
end

local function doExport()
  if opInFlight or not status.bwAvailable then return end

  local decryptCmd = noctalia.getConfig("decrypt_cmd")
  local outPath = noctalia.getConfig("export_out_path")
  if type(decryptCmd) ~= "string" or decryptCmd == "" then
    noctalia.notifyError("Bitwarden", "Decrypt command not configured in settings")
    return
  end
  if type(outPath) ~= "string" or outPath == "" then
    noctalia.notifyError("Bitwarden", "Export path not configured in settings")
    return
  end

  local destination = shellQuote(outPath)
  if outPath:sub(1, 2) == "~/" then
    destination = '"$HOME"/' .. shellQuote(outPath:sub(3))
  end

  -- Never place the master password in the shell command arguments.
  -- The configured decrypt command is executed by the shell and returns it via stdout.
  local exportCmd = table.concat({
    "set -eu",
    "umask 077",
    `out={destination}`,
    'mkdir -p -- "$(dirname -- "$out")"',
    'tmp=$(mktemp "${out}.tmp.XXXXXX")',
    "trap 'rm -f -- \"$tmp\"' EXIT HUP INT TERM",
    `BW_PASSWORD=$({decryptCmd})`,
    'test -n "$BW_PASSWORD"',
    "export BW_PASSWORD",
    "BW_SESSION=$(bw unlock --raw --passwordenv BW_PASSWORD)",
    "export BW_SESSION",
    'bw --raw export --format json > "$tmp"',
    'chmod 600 -- "$tmp"',
    'mv -f -- "$tmp" "$out"',
    "trap - EXIT HUP INT TERM",
  }, "; ")

  opInFlight = true
  noctalia.runAsync(exportCmd, function(expRes)
    opInFlight = false
    if type(expRes) ~= "table" or expRes.exitCode ~= 0 then
      local errMsg = (type(expRes) == "table" and type(expRes.stderr) == "string" and expRes.stderr ~= "") and expRes.stderr or "CLI error"
      noctalia.notifyError("Bitwarden", "Export failed: " .. errMsg)
    else
      noctalia.notify("Bitwarden", `Vault exported to {outPath}`)
    end
  end, 60000)
end
function onIpc(event, payload)
  if event == "toggle_menu" then
    if status.vault == "unlocked" then
      openVaultLauncher(true)
    elseif not syncInFlight then
      doUnlockCmd(true)
    end
  elseif event == "unlock_cmd" then
    doUnlockCmd(false)
  elseif event == "lock" then
    doLock()
  elseif event == "sync" then
    doSync()
  elseif event == "export" then
    doExport()
  elseif event == "ensure_serve" or event == "serve" then
    ensureServe(true)
    pollStatus()
  elseif event == "status" then
    pollStatus()
  elseif event == "copy" then
    local id = payload.id
    local field = payload.field or "password"
    copyItemField(id, field, payload.name)
  elseif event == "autotype" then
    local id = payload.id
    doAutotype(id)
  elseif event == "generate" then
    local mode = "password"
    if type(payload) == "table" and type(payload.mode) == "string" and payload.mode ~= "" then
      mode = payload.mode
    end
    doGenerate(mode)
  end
end

noctalia.state.watch("command", function(cmd)
  local action = if type(cmd) == "table" and cmd.action ~= nil then cmd.action else cmd
  if type(action) == "string" then
    onIpc(action, if type(cmd) == "table" then cmd else nil)
  end
end)

function update()
  tickCount += 1
  if serveStartCooldown > 0 then serveStartCooldown -= 1 end

  if pendingClear ~= nil then
    pendingClear.ticksLeft -= 1
    if pendingClear.ticksLeft <= 0 then
      local currentText = noctalia.string.trim(noctalia.clipboardText() or "")
      local targetText = noctalia.string.trim(pendingClear.text or "")
      if currentText == targetText and currentText ~= "" then
        noctalia.copyToClipboard("", "text/plain;charset=utf-8")
        noctalia.runAsync("noctalia msg clipboard-clear")
      end
      pendingClear = nil
    end
  end

  if pendingQuietLock and not opInFlight then
    pendingQuietLock = false
    doLock(true)
  elseif status.vault == "unlocked" and unlockDeadlineTick ~= nil and tickCount >= unlockDeadlineTick and not opInFlight then
    unlockDeadlineTick = nil
    log("vault timeout: locking")
    doLock(true)
  end

  if tickCount == 1 then
    status.bwAvailable = noctalia.commandExists("bw")
    if not status.bwAvailable then
      setStatus({ vault = "offline", serveUp = false, error = "bw not found" })
      return
    end
    publishStatus()
    pollStatus()
  elseif tickCount % STATUS_TICKS == 0 then
    pollStatus()
  end
end

function onExit(_signal)
  if status.vault == "unlocked" then
    noctalia.runAsync(`curl -sS -m 5 -X POST http://127.0.0.1:{SERVE_PORT}/lock >/dev/null 2>&1 &`)
  end
end

publishStatus()
