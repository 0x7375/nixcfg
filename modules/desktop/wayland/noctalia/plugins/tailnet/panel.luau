--!nonstrict
local PANEL_HEIGHT = 540
local snapshot = nil
local isOpen = false
local cmdNonce = 0
local filterText = ""
local OS_GLYPHS = {
  linux = "device-desktop", windows = "device-desktop", macos = "device-laptop",
  ios = "device-mobile", android = "device-mobile",
}
local function shq(value)
  local quoted = tostring(value or ""):gsub("'", "'\\''")
  return `'{quoted}'`
end
local function tr(key, subst)
  return noctalia.tr(key, subst)
end
local function sendCmd(action, extra)
  cmdNonce += 1
  local cmd = { n = cmdNonce, action = action }
  if extra then for k, v in extra do cmd[k] = v end end
  noctalia.state.set("tn.cmd", noctalia.json.encode(cmd))
end
local function copyValue(value, name, isName)
  if value == "" then return end
  noctalia.copyToClipboard(value, "text/plain")
  noctalia.notify(tr("toast.title"), tr(isName and "toast.copied-name" or "toast.copied-ip", { host = name, value = value }))
end
local function stateOf()
  return snapshot and snapshot.state or "stopped"
end
local function setPref(pref, enabled)
  sendCmd("set_pref", { pref = pref, enabled = enabled })
end
local function togglePeerExitNode(peer)
  if peer.exitNode then sendCmd("exit_clear")
  elseif peer.ip ~= "" then sendCmd("exit_set", { ip = peer.ip }) end
end
local function pingPeer(peer)
  if peer.ip ~= "" then sendCmd("ping", { ip = peer.ip, name = peer.name }) end
end
local function sshPeer(peer)
  local host = peer.ip ~= "" and peer.ip or peer.shortName
  if host == "" then return end
  local user = noctalia.string.trim(noctalia.getConfig("ssh_username") or "")
  if user ~= "" and not user:match("^[%w%._%-]+$") then
    noctalia.notifyError(tr("toast.title"), tr("toast.invalid-username"))
    return
  end
  local target = user ~= "" and `{user}@{host}` or host
  noctalia.runInTerminal(`ssh {shq(target)}`)
end
local function header()
  local state = stateOf()
  local running = state == "running"
  local stateColor = running and "primary" or ((state == "stopped" or state == "switching") and "outline_variant" or "error")
  return ui.row({ gap = 8, align = "center" }, {
    ui.image({ path = noctalia.isDarkMode() and "icon.svg" or "icon-light.svg", width = 20, height = 20, fit = "contain" }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = tr("panel.title"), fontSize = 16, fontWeight = "bold" }),
      ui.label({ text = tr(`state.{state}`), fontSize = 12, color = stateColor }),
    }),
    ui.button({ glyph = "download", variant = "ghost", controlSize = "sm", enabled = running, tooltip = tr("panel.taildrop"), onClick = "onTaildrop" }),
    ui.button({ glyph = running and "plug-connected-x" or "plug-connected", variant = running and "outline" or "primary",
      controlSize = "sm", enabled = state == "running" or state == "stopped", tooltip = running and tr("panel.disconnect") or tr("panel.connect"), onClick = running and "onDown" or "onUp" }),
    ui.button({ glyph = "external-link", variant = "ghost", controlSize = "sm", enabled = state ~= "switching", tooltip = tr("panel.admin"), onClick = "onAdmin" }),
    ui.button({ glyph = "refresh", variant = "outline", controlSize = "sm", enabled = state ~= "switching", tooltip = tr("panel.refresh"), onClick = "onRefresh" }),
  })
end
local function profileRow()
  local profiles = snapshot and snapshot.profiles or {}
  if #profiles < 2 and (#profiles == 0 or profiles[1].selected) then return nil end
  local options, counts = {}, {}
  local selectedIndex = 0
  local selected = false
  for i, profile in ipairs(profiles) do
    local label = profile.tailnet ~= "" and profile.tailnet or profile.id
    local account = profile.nickname ~= "" and profile.nickname or profile.account
    if account ~= "" and account ~= label then label = `{label} · {account}` end
    options[i] = label
    counts[label] = (counts[label] or 0) + 1
    if profile.selected then selectedIndex = i - 1; selected = true end
  end
  for i, label in ipairs(options) do
    if counts[label] > 1 then options[i] = `{label} ({profiles[i].id})` end
  end
  local offset = 1
  if not selected then
    table.insert(options, 1, tr("panel.select-tailnet"))
    offset = 0
  end
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "network", size = 16, color = "primary" }),
    ui.select({ key = "tailnet-profile", options = options, selectedIndex = selectedIndex,
      controlSize = "sm", flexGrow = 1, enabled = stateOf() ~= "switching",
      onChange = function(index, _text)
        local i = tonumber(index)
        local profile = i and profiles[i + offset]
        if profile and not profile.selected then sendCmd("switch", { id = profile.id }) end
      end,
    }),
  })
end
local PREFS = {
  { key = "shieldsUp", label = "shields-up", glyph = "shield" },
  { key = "acceptRoutes", label = "accept-routes", glyph = "route" },
  { key = "runSSH", label = "run-ssh", glyph = "server" },
  { key = "advertiseExitNode", label = "advertise-exit-node", glyph = "world-upload" },
  { key = "allowLanAccess", label = "allow-lan-access", glyph = "network" },
}
local function prefsRow()
  local prefs = snapshot and snapshot.prefs
  if not prefs then return nil end
  local buttons = {}
  for _, pref in PREFS do
    local on = prefs[pref.key] == true
    table.insert(buttons, ui.button({ glyph = pref.glyph, variant = "ghost", controlSize = "sm", selected = on, flexGrow = 1,
      tooltip = `{tr(`pref.{pref.label}`)} — {tr(on and "pref.on" or "pref.off")}`,
      onClick = function() setPref(pref.key, not on) end }))
  end
  return ui.row({ gap = 4 }, buttons)
end
local function healthBox()
  local health = snapshot and snapshot.health or {}
  if #health == 0 then return nil end
  local children = {}
  for _, warning in health do
    table.insert(children, ui.label({ text = warning, fontSize = 11, color = "error/0.9", maxLines = 3 }))
  end
  return ui.column({ gap = 3, padding = 8, fill = "error/0.1", radius = 8 }, children)
end
local function selfRow()
  if not snapshot or stateOf() ~= "running" then return nil end
  return ui.row({ gap = 8, padding = 8, align = "center", fill = "primary/0.12", radius = 8 }, {
    ui.glyph({ name = "home", size = 14, color = "primary" }),
    ui.column({ gap = 1, flexGrow = 1 }, {
      ui.label({ text = snapshot.self.name, fontWeight = "bold", fontSize = 13, maxLines = 1 }),
      ui.label({ text = snapshot.self.ip, fontSize = 11, color = "on_surface/0.65", maxLines = 1 }),
    }),
    ui.button({ glyph = "copy", variant = "ghost", controlSize = "sm", tooltip = tr("panel.copy-ip"), onClick = "onCopySelfIp" }),
    ui.button({ glyph = "tag", variant = "ghost", controlSize = "sm", tooltip = tr("panel.copy-name"), onClick = "onCopySelfName" }),
  })
end
local function exitNodeRow()
  if not snapshot or not snapshot.exitNode then return nil end
  return ui.row({ gap = 8, padding = 8, align = "center", fill = "secondary/0.15", radius = 8 }, {
    ui.glyph({ name = "world", size = 14, color = "secondary" }),
    ui.label({ text = tr("panel.exit-node-active", { name = snapshot.exitNode.name }), fontSize = 12, flexGrow = 1, maxLines = 1 }),
    ui.button({ text = tr("panel.exit-node-clear"), variant = "outline", controlSize = "sm", onClick = "onExitClear" }),
  })
end
local function matchesFilter(peer)
  if filterText == "" then return true end
  return (`{peer.name} {peer.ip} {peer.os}`):lower():find(filterText:lower(), 1, true) ~= nil
end
local function peerRow(peer)
  local buttons = {
    ui.button({ glyph = "copy", variant = "ghost", controlSize = "sm", enabled = peer.ip ~= "", tooltip = tr("panel.copy-ip-value", { value = peer.ip }),
      onClick = function() copyValue(peer.ip, peer.name, false) end }),
    ui.button({ glyph = "tag", variant = "ghost", controlSize = "sm", enabled = peer.shortName ~= "", tooltip = tr("panel.copy-name-value", { value = peer.shortName }),
      onClick = function() copyValue(peer.shortName, peer.name, true) end }),
    ui.button({ glyph = "activity", variant = "ghost", controlSize = "sm", enabled = peer.online and peer.ip ~= "", tooltip = tr("panel.ping"),
      onClick = function() pingPeer(peer) end }),
    ui.button({ glyph = "terminal-2", variant = "ghost", controlSize = "sm", enabled = peer.online and peer.shortName ~= "", tooltip = tr("panel.ssh"),
      onClick = function() sshPeer(peer) end }),
  }
  if peer.exitNodeOption then
    table.insert(buttons, ui.button({ glyph = "world", variant = "ghost", controlSize = "sm", selected = peer.exitNode, enabled = peer.online or peer.exitNode,
      tooltip = peer.exitNode and tr("panel.exit-node-clear") or tr("panel.exit-node-use"), onClick = function() togglePeerExitNode(peer) end }))
  end
  local base = peer.ip ~= "" and peer.ip or (peer.online and tr("launcher.online") or tr("launcher.offline"))
  if not peer.online and peer.lastSeen and peer.lastSeen ~= "" then base = `{base} · {tr("peer.last-seen", { value = peer.lastSeen })}` end
  local children = {
    ui.box({ width = 8, height = 8, radius = 4, fill = peer.online and "primary" or "outline_variant" }),
    ui.glyph({ name = OS_GLYPHS[peer.os:lower()] or "device-desktop", size = 14, color = "on_surface/0.7" }),
    ui.column({ gap = 1, flexGrow = 1 }, {
      ui.label({ text = peer.name, fontWeight = "bold", fontSize = 13, maxLines = 1 }),
      ui.label({ text = base, fontSize = 11, color = "on_surface/0.65", maxLines = 1 }),
    }),
  }
  for _, b in buttons do table.insert(children, b) end
  return ui.row({ key = `peer-{peer.shortName ~= "" and peer.shortName or peer.name}`, gap = 8, padding = 8, align = "center",
    fill = "surface_container/0.5", radius = 8, opacity = peer.online and 1 or 0.6 }, children)
end
local function peerList()
  local rows = {}
  if snapshot and stateOf() == "running" then
    for _, peer in snapshot.peers do
      if matchesFilter(peer) then table.insert(rows, peerRow(peer)) end
    end
  end
  if #rows == 0 and stateOf() ~= "switching" then
    table.insert(rows, ui.label({ text = tr("panel.no-peers"), fontSize = 12, color = "on_surface/0.6" }))
  end
  return ui.scroll({ gap = 6, flexGrow = 1 }, rows)
end
local function needsLoginBox()
  if stateOf() ~= "needs-login" then return nil end
  return ui.column({ gap = 8, padding = 10, fill = "error/0.12", radius = 8 }, {
    ui.label({ text = tr("panel.needs-login"), fontSize = 12, maxLines = 3 }),
    ui.button({ text = tr("panel.login"), variant = "primary", controlSize = "sm", enabled = snapshot ~= nil and snapshot.authUrl ~= "", onClick = "onLogin" }),
  })
end
local function render()
  if not isOpen then return end
  local children = { header() }
  local function push(node) if node then table.insert(children, node) end end
  push(profileRow())
  push(needsLoginBox())
  push(healthBox())
  push(selfRow())
  push(prefsRow())
  push(exitNodeRow())
  if snapshot and stateOf() == "running" then
    table.insert(children, ui.row({ gap = 6, align = "center" }, {
      ui.input({ key = "filter", value = filterText, placeholder = tr("panel.filter", { online = snapshot.online, total = snapshot.total }), controlSize = "sm", onChange = "onFilter", flexGrow = 1 }),
    }))
  end
  table.insert(children, peerList())
  if snapshot then
    table.insert(children, ui.column({ paddingV = 8 }, {
      ui.label({ text = tr("panel.last-check-info", { value = snapshot.checkedAt }), fontSize = 11, color = "on_surface/0.55" }),
    }))
  end
  panel.render(ui.column({ gap = 10, padding = 14, height = PANEL_HEIGHT }, children))
end
noctalia.state.watch("tn.snapshot", function(encoded)
  snapshot = encoded and noctalia.json.decode(encoded) or nil
  if stateOf() == "switching" then filterText = "" end
  render()
end)
function onOpen(_context)
  isOpen = true
  local encoded = noctalia.state.get("tn.snapshot")
  snapshot = encoded and noctalia.json.decode(encoded) or nil
  render()
  sendCmd("refresh")
end
function onClose() isOpen = false end
function onFilter(value) filterText = noctalia.string.trim(value); render() end
function onRefresh() sendCmd("refresh") end
function onUp() sendCmd("up") end
function onDown() sendCmd("down") end
function onLogin() if snapshot and snapshot.authUrl ~= "" then sendCmd("login", { url = snapshot.authUrl }) end end
function onExitClear() sendCmd("exit_clear") end
function onTaildrop() sendCmd("taildrop_get") end
function onAdmin() sendCmd("open_admin") end
function onCopySelfIp() if snapshot then copyValue(snapshot.self.ip, snapshot.self.name, false) end end
function onCopySelfName() if snapshot then copyValue(snapshot.self.dnsName, snapshot.self.name, true) end end
