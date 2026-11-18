--!nonstrict
local STUCK_MS = 30000
local pollGeneration = 0
local pollPending = false
local pollStartedAt = 0
local pollAgain = false
local switchPending = false
local lastProfiles = {}
local installed = nil
local function trim(s)
  return noctalia.string.trim(s or "")
end
local function shq(value)
  local quoted = tostring(value or ""):gsub("'", "'\\''")
  return `'{quoted}'`
end
local function tsBin()
  local configured = trim(noctalia.getConfig("tailscale_bin"))
  return configured ~= "" and shq(noctalia.expandPath(configured)) or "tailscale"
end
local function shortName(dnsName)
  return trim(dnsName):match("^([^%.]+)") or ""
end
local function displayName(hostName, dnsName)
  hostName = trim(hostName)
  if hostName ~= "" and hostName:lower() ~= "localhost" then return hostName end
  local label = shortName(dnsName)
  return label ~= "" and label or hostName
end
local function firstIPv4(ips)
  for _, ip in (ips or {}) do
    if ip:match("^100%.") then return ip end
  end
  return (ips or {})[1] or ""
end
local function emptySnapshot(state, detail)
  return {
    state = state, detail = detail or "", checkedAt = noctalia.formatTime("%H:%M:%S"),
    profiles = {}, authUrl = "", self = { name = "", ip = "", dnsName = "" },
    peers = {}, online = 0, total = 0, exitNode = nil, health = {}, prefs = nil,
  }
end
local function publish(snapshot, generation)
  if generation and generation ~= pollGeneration then return end
  pollPending = false
  pollStartedAt = 0
  lastProfiles = snapshot.profiles or {}
  local encoded = noctalia.json.encode(snapshot)
  if encoded then noctalia.state.set("tn.snapshot", encoded) end
  if pollAgain then
    pollAgain = false
    poll()
  end
end
local function buildSnapshot(data)
  local snapshot = emptySnapshot("running")
  local backend = data.BackendState or ""
  if backend == "NeedsLogin" then
    snapshot.state = "needs-login"
    snapshot.authUrl = trim(data.AuthURL)
    return snapshot
  end
  if backend ~= "Running" then
    snapshot.state = "stopped"
    return snapshot
  end
  local selfNode = data.Self or {}
  snapshot.self = {
    name = displayName(selfNode.HostName, selfNode.DNSName),
    ip = firstIPv4(selfNode.TailscaleIPs), dnsName = shortName(selfNode.DNSName),
  }
  for _, warning in (data.Health or {}) do
    local text = trim(warning)
    if text ~= "" then table.insert(snapshot.health, text) end
  end
  local hideMullvad = noctalia.getConfig("hide_mullvad") ~= false
  local hideOffline = noctalia.getConfig("hide_offline") == true
  for _, peer in (data.Peer or {}) do
    local dns = trim(peer.DNSName)
    if hideMullvad and dns:find(".mullvad.ts.net", 1, true) then continue end
    local online = peer.Online == true
    if hideOffline and not online then continue end
    local lastSeen = trim(peer.LastSeen)
    if lastSeen ~= "" and lastSeen:sub(1, 4) ~= "0001" then
      lastSeen = lastSeen:sub(1, 16):gsub("T", " ")
    else
      lastSeen = ""
    end
    table.insert(snapshot.peers, {
      name = displayName(peer.HostName, dns), shortName = shortName(dns),
      ip = firstIPv4(peer.TailscaleIPs), online = online, os = trim(peer.OS),
      lastSeen = lastSeen, exitNodeOption = peer.ExitNodeOption == true,
      exitNode = peer.ExitNode == true,
    })
    snapshot.total += 1
    if online then snapshot.online += 1 end
  end
  local nameCount = {}
  for _, peer in snapshot.peers do nameCount[peer.name] = (nameCount[peer.name] or 0) + 1 end
  for _, peer in snapshot.peers do
    if nameCount[peer.name] > 1 and peer.shortName ~= "" then peer.name = peer.shortName end
  end
  table.sort(snapshot.peers, function(a, b)
    if a.online ~= b.online then return a.online end
    return a.name:lower() < b.name:lower()
  end)
  local exitStatus = data.ExitNodeStatus
  if exitStatus then
    local exitIp = firstIPv4(exitStatus.TailscaleIPs)
    local exitName = exitIp
    for _, peer in snapshot.peers do
      if peer.exitNode then exitName = peer.name; break end
    end
    snapshot.exitNode = { name = exitName, ip = exitIp, online = exitStatus.Online == true }
  end
  return snapshot
end
local function readPrefs(snapshot, generation, done)
  local launched = noctalia.runAsync(`{tsBin()} debug prefs`, function(result)
    if generation ~= pollGeneration then return end
    local data = result.exitCode == 0 and not result.stdoutTruncated and noctalia.json.decode(result.stdout) or nil
    if data then
      local advertises = false
      for _, route in (data.AdvertiseRoutes or {}) do
        if route == "0.0.0.0/0" or route == "::/0" then advertises = true; break end
      end
      snapshot.prefs = {
        shieldsUp = data.ShieldsUp == true, acceptRoutes = data.RouteAll == true,
        runSSH = data.RunSSH == true, advertiseExitNode = advertises,
        allowLanAccess = data.ExitNodeAllowLANAccess == true,
      }
    end
    done()
  end, 10000)
  if not launched then done() end
end
local function publishWithProfiles(snapshot, generation)
  local launched = noctalia.runAsync(`{tsBin()} switch --list --json`, function(result)
    if generation ~= pollGeneration then return end
    local profiles = result.exitCode == 0 and not result.timedOut
      and not result.stdoutTruncated and noctalia.json.decode(result.stdout) or nil
    if type(profiles) == "table" then
      for _, profile in ipairs(profiles) do
        if type(profile) == "table" and type(profile.id) == "string" and profile.id ~= "" then
          table.insert(snapshot.profiles, {
            id = profile.id, nickname = trim(profile.nickname), tailnet = trim(profile.tailnet),
            account = trim(profile.account), selected = profile.selected == true,
          })
        end
      end
      table.sort(snapshot.profiles, function(a, b) return a.id < b.id end)
    end
    publish(snapshot, generation)
  end, 5000)
  if not launched then publish(snapshot, generation) end
end
function poll()
  if switchPending then return end
  if pollPending and noctalia.nowMs() - pollStartedAt < STUCK_MS then
    pollAgain = true
    return
  end
  pollPending = true
  pollStartedAt = noctalia.nowMs()
  pollGeneration += 1
  local generation = pollGeneration
  if installed == nil then
    local configured = trim(noctalia.getConfig("tailscale_bin"))
    installed = configured ~= "" and noctalia.fileExists(noctalia.expandPath(configured))
      or noctalia.commandExists("tailscale")
  end
  if not installed then publish(emptySnapshot("not-installed"), generation); return end
  local launched = noctalia.runAsync(`{tsBin()} status --json`, function(result)
    if generation ~= pollGeneration then return end
    if result.exitCode ~= 0 or result.timedOut then
      publishWithProfiles(emptySnapshot("stopped", trim(result.stderr)), generation)
      return
    end
    if result.stdoutTruncated then
      publishWithProfiles(emptySnapshot("error", "status output truncated"), generation)
      return
    end
    local data = noctalia.json.decode(result.stdout)
    if not data then
      publishWithProfiles(emptySnapshot("error", "invalid status JSON"), generation)
      return
    end
    local snapshot = buildSnapshot(data)
    if snapshot.state ~= "running" then publishWithProfiles(snapshot, generation); return end
    readPrefs(snapshot, generation, function() publishWithProfiles(snapshot, generation) end)
  end, 10000)
  if not launched then publishWithProfiles(emptySnapshot("error", "failed to run tailscale"), generation) end
end
local function runThenRefresh(cmdline, okKey, failKey, subst)
  local launched = noctalia.runAsync(cmdline, function(result)
    if result.exitCode == 0 and not result.timedOut then
      if okKey then noctalia.notify(noctalia.tr("toast.title"), noctalia.tr(okKey, subst)) end
    else
      local err = trim(result.stderr)
      noctalia.notifyError(noctalia.tr("toast.title"), err ~= "" and err or noctalia.tr(failKey or "toast.failed"))
    end
    poll()
  end, 30000)
  if not launched then noctalia.notifyError(noctalia.tr("toast.title"), noctalia.tr(failKey or "toast.failed")) end
end
local function switchProfile(id)
  if switchPending or type(id) ~= "string" or not id:match("^[%w][%w_%-]*$") then return end
  local target = nil
  for _, profile in lastProfiles do
    if profile.id == id and not profile.selected then target = profile; break end
  end
  if not target then return end
  switchPending = true
  pollGeneration += 1
  pollAgain = false
  local snapshot = emptySnapshot("switching")
  snapshot.profiles = lastProfiles
  publish(snapshot, pollGeneration)
  local function finish(errorMessage)
    if errorMessage then noctalia.notifyError(noctalia.tr("toast.title"), errorMessage) end
    switchPending = false
    poll()
  end
  local launched = noctalia.runAsync(`{tsBin()} switch {shq(id)}`, function(result)
    if result.exitCode == 0 and not result.timedOut then finish()
    else
      local detail = trim(result.stderr)
      if detail == "" then detail = trim(result.stdout) end
      finish(detail ~= "" and detail or noctalia.tr("toast.switch-failed"))
    end
  end, 30000)
  if not launched then finish(noctalia.tr("toast.switch-failed")) end
end
local function receiveTaildrop()
  local dir = trim(noctalia.getConfig("taildrop_dir"))
  local function go(target)
    local pre = {}
    for _, f in (noctalia.listDir(target) or {}) do pre[f] = true end
    noctalia.runAsync(`{tsBin()} file get {shq(target)}`, function(result)
      if result.exitCode ~= 0 then
        local err = trim(result.stderr)
        noctalia.notifyError(noctalia.tr("toast.title"), err ~= "" and err or noctalia.tr("taildrop.failed"))
        return
      end
      local fresh = {}
      for _, f in (noctalia.listDir(target) or {}) do
        if not pre[f] then table.insert(fresh, f) end
      end
      if #fresh > 0 then
        noctalia.notify(noctalia.tr("toast.title"), `{noctalia.tr("taildrop.received", { count = #fresh, dir = target })}\n{table.concat(fresh, "\n")}`)
      else
        noctalia.notify(noctalia.tr("toast.title"), noctalia.tr("taildrop.none"))
      end
    end, 60000)
  end
  if dir ~= "" then go(noctalia.expandPath(dir))
  else
    noctalia.runAsync("xdg-user-dir DOWNLOAD", function(result)
      local target = trim(result.stdout)
      go(target ~= "" and target or noctalia.expandPath("~/Downloads"))
    end, 5000)
  end
end
local function pingPeer(ip, name)
  noctalia.runAsync(`{tsBin()} ping -c 3 {shq(ip)}`, function(result)
    local out, err = trim(result.stdout), trim(result.stderr)
    local pong = nil
    for line in out:gmatch("[^\n]+") do
      if line:match("^%s*pong") then pong = trim(line) end
    end
    if pong then
      local combined = `{out}\n{err}`
      local relayed = combined:find("direct connection not established", 1, true)
      noctalia.notify(`Ping {name}`, relayed and `{pong}\n{noctalia.tr("ping.relayed")}` or pong)
    else noctalia.notifyError(`Ping {name}`, err ~= "" and err or noctalia.tr("toast.failed")) end
  end, 25000)
end
local function openUrl(url)
  if url and url:match("^https?://[%w%.%-%_%~%:%/%?%#%[%]%@%!%$%&%'%(%)%*%+%,%;%=%%]+$") then
    local quoted = shq(url)
    noctalia.runAsync(`gio open {quoted} || xdg-open {quoted}`)
  end
end
local PREF_FLAGS = {
  shieldsUp = { flag = "shields-up", label = "shields-up" },
  acceptRoutes = { flag = "accept-routes", label = "accept-routes" },
  runSSH = { flag = "ssh", label = "run-ssh" },
  advertiseExitNode = { flag = "advertise-exit-node", label = "advertise-exit-node" },
  allowLanAccess = { flag = "exit-node-allow-lan-access", label = "allow-lan-access" },
}
noctalia.state.watch("tn.cmd", function(raw)
  local cmd = raw and noctalia.json.decode(raw) or nil
  if not cmd or not cmd.action or switchPending then return end
  local bin = tsBin()
  if cmd.action == "refresh" then poll()
  elseif cmd.action == "switch" then switchProfile(cmd.id)
  elseif cmd.action == "up" then runThenRefresh(`{bin} up`, "toast.connected")
  elseif cmd.action == "down" then runThenRefresh(`{bin} down`, "toast.disconnected")
  elseif cmd.action == "exit_set" and cmd.ip then runThenRefresh(`{bin} set --exit-node={shq(cmd.ip)}`, "toast.exit-node-enabled")
  elseif cmd.action == "exit_clear" then runThenRefresh(`{bin} set --exit-node=`, "toast.exit-node-disabled")
  elseif cmd.action == "set_pref" then
    local pref = PREF_FLAGS[cmd.pref or ""]
    if pref then
      local on = cmd.enabled == true
      runThenRefresh(`{bin} set --{pref.flag}={on and "true" or "false"}`, on and "toast.pref-on" or "toast.pref-off", nil, { name = noctalia.tr(`pref.{pref.label}`) })
    end
  elseif cmd.action == "taildrop_get" then receiveTaildrop()
  elseif cmd.action == "ping" and cmd.ip then pingPeer(cmd.ip, cmd.name or cmd.ip)
  elseif cmd.action == "login" then openUrl(cmd.url)
  elseif cmd.action == "open_admin" then
    local configured = trim(noctalia.getConfig("admin_url"))
    openUrl(configured ~= "" and configured or "https://login.tailscale.com/admin/machines")
  else noctalia.log(`[tailnet] unknown command: {cmd.action}`) end
end)
function onConfigChanged()
  installed = nil
  poll()
end
function onIpc(event)
  if switchPending then return end
  if event == "refresh" then poll()
  elseif event == "up" then runThenRefresh(`{tsBin()} up`, "toast.connected")
  elseif event == "down" then runThenRefresh(`{tsBin()} down`, "toast.disconnected") end
end
function update()
  local seconds = tonumber(noctalia.getConfig("poll_interval")) or 5
  noctalia.setUpdateInterval(math.clamp(seconds, 1, 60) * 1000)
  poll()
end
