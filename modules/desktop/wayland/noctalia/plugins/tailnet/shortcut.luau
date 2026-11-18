--!nonstrict
local snapshot = nil
local cmdNonce = 0
local function render()
  local state = snapshot and snapshot.state or "stopped"
  shortcut.setLabel(noctalia.tr("shortcut.label"))
  shortcut.setIcon("topology-star-3", "topology-star-3")
  shortcut.setActive(state == "running")
  shortcut.setEnabled(state == "running" or state == "stopped")
end
noctalia.state.watch("tn.snapshot", function(encoded)
  snapshot = encoded and noctalia.json.decode(encoded) or nil
  render()
end)
function onClick()
  local state = snapshot and snapshot.state or "stopped"
  if state ~= "running" and state ~= "stopped" then return end
  cmdNonce += 1
  local action = state == "running" and "down" or "up"
  noctalia.state.set("tn.cmd", noctalia.json.encode({ n = cmdNonce, action = action }))
end
render()
