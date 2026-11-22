--!nonstrict
-- Bitwarden: keyboard-first, read/write vault panel. No local HTTP API.
-- Escape is reserved by Noctalia. Alt+H returns; Ctrl+O opens the editor.
-- Ctrl+H is left uncaptured so it cannot interfere with text editing.
-- A focused input receives plain Space normally; on details Space toggles reveal.
-- The service unlocks the vault before showing this panel.

noctalia.setUpdateInterval(1000)

local backend = (noctalia.pluginDir() or "") .. "/client.py"
local iconWorker = (noctalia.pluginDir() or "") .. "/icons.py"
local runtimeDir = ""
-- The backend returns the verified owner-only runtime path on first open.
local requestPath = ""
local mode = "search"  -- search | detail | edit
local vault = "loading"
local busy = false  -- true only for unlock, save, sync, lock
local saving = false
local openingItem = false
local message = ""
local query = ""
local items = {}
local visible = {}
local selected = 1
local detail = nil
local selectedItem = nil
local entryRows = {}
local selectedField = 1
local revealedFields = {} -- plaintext only while this item is open; never persisted
local nextTotpRefresh = 0 -- only TOTP codes refresh when their time slot changes
local totpRefreshPending = false
local draft = nil
local draftInitial = nil
local draftChanged = false
local pendingSaveRefresh = false
local createType = 1
local searchKey = 0
local editKey = 0
local editFocus = 1
local editFocusSerial = 0
local editInputs = 0
local knownEpoch = 0
local heldKey = nil
local repeatElapsed = 0
local repeatCount = 0
local actionBindings = {}
local BODY_WIDTH = 500
local LIST_WIDTH = 484
-- Reserve room for the scroll indicator instead of letting it cover edit inputs.
local EDIT_SCROLL_PADDING = 8
local EDIT_SCROLL_GUTTER = 16
local EDIT_FIELD_WIDTH = BODY_WIDTH - 2 * EDIT_SCROLL_PADDING - EDIT_SCROLL_GUTTER
local openGeneration = 0
local iconPaths = {}
local iconAttempted = {}
local iconsRunning = false
local useWebsiteIcons = false
local render
local fetchIcons
local loadDetail

local function readBindings()
  for _, action in ipairs({ "up", "down", "tab_next", "tab_previous", "validate", "save" }) do
    local value = noctalia.getSetting("keybinds." .. action)
    if type(value) == "string" then value = { value } end
    actionBindings[action] = if type(value) == "table" then value else {}
  end
end

local function bindingMatches(action, chord)
  local value = string.lower(chord)
  for _, candidate in ipairs(actionBindings[action] or {}) do
    if type(candidate) == "string" and string.lower(candidate) == value then return true end
  end
  return false
end

readBindings()

function onConfigChanged()
  readBindings()
end

local function shorten(text, maximum)
  if type(text) ~= "string" then return "" end
  local s = noctalia.string.trim(text:gsub("[%c]+", " "))
  if #s > maximum then s = s:sub(1, maximum) .. "…" end
  return s
end

local function setError(errorText)
  message = if type(errorText) == "string" then errorText else "Operation failed"
end

-- Lightweight reads do not disable the whole interface. Exclusive operations
-- only block conflicting writes; details and copying use the in-memory backend.
local function call(args, done, blocking, onError)
  if blocking and busy then return false end
  if blocking then busy = true end
  local argv = { "python3", backend }
  for _, argument in ipairs(args) do table.insert(argv, argument) end
  local generation = openGeneration
  local started = noctalia.runAsync(argv, function(result)
    if generation ~= openGeneration then return end
    if blocking then busy = false end
    local problem = nil
    local decoded = nil
    if result.exitCode ~= 0 or result.timedOut or result.stdoutTruncated then
      problem = "Bitwarden helper failed or timed out"
    else
      decoded = noctalia.json.decode(result.stdout or "")
      if type(decoded) ~= "table" then
        problem = "Invalid response from Bitwarden"
      elseif decoded.ok ~= true then
        problem = decoded.error or "Bitwarden command failed"
      end
    end
    if problem ~= nil then
      setError(problem)
      if problem == "Vault locked" then
        vault = "locked"
        noctalia.state.set("vault_ready", false)
        items = {}
        visible = {}
        detail = nil
        draft = nil
        mode = "search"
      end
      if onError ~= nil then onError(problem) end
    else
      message = ""
      if done ~= nil then done(decoded.data) end
    end
    render()
  end, 60000)
  if not started then
    if blocking then busy = false end
    setError("Unable to run vault helper")
    if onError ~= nil then onError(message) end
    render()
  elseif blocking then
    render()
  end
  return started
end

local function writeRequest(payload)
  if requestPath == "" then return false end
  local json = noctalia.json.encode(payload)
  if type(json) ~= "string" then return false end
  local ok = noctalia.writeFile(requestPath, json)
  return ok == true
end

local function filterItems()
  local scored = {}
  local search = noctalia.string.trim(query)
  for _, item in ipairs(items) do
    local points = 0
    if search ~= "" then
      local inName = noctalia.fuzzyScore(search, item.name or "")
      local inOther = noctalia.fuzzyScore(search, item.search or "")
      if inName ~= nil then points = 1000000 + inName
      elseif inOther ~= nil then points = inOther
      else continue end
    end
    table.insert(scored, { item = item, points = points })
  end
  if search ~= "" then
    table.sort(scored, function(a, b)
      if a.points ~= b.points then return a.points > b.points end
      return (a.item.name or "") < (b.item.name or "")
    end)
  end
  visible = {}
  for i, entry in ipairs(scored) do
    if i > 100 then break end
    table.insert(visible, entry.item)
  end
  if selected > #visible then selected = #visible end
  if selected < 1 then selected = 1 end
end

loadDetail = function(id)
  if mode == "detail" and selectedItem == id and (openingItem or detail ~= nil) then return end
  selectedItem = id
  revealedFields = {}
  nextTotpRefresh = 0
  totpRefreshPending = false
  detail = nil
  entryRows = {}
  mode = "detail"
  selectedField = 1
  openingItem = true
  render()
  call({ "detail", id }, function(data)
    if mode ~= "detail" or selectedItem ~= id then return end
    openingItem = false
    detail = data
    entryRows = if type(data) == "table" and type(data.rows) == "table" then data.rows else {}
    if #entryRows == 0 then selectedField = 0 else selectedField = 1 end
  end, false, function()
    openingItem = false
  end)
end

local function applyOpen(data)
  vault = data.status or "locked"
  if vault == "unlocked" then
    local previousId = if visible[selected] ~= nil then visible[selected].id else nil
    items = data.items or {}
    filterItems()
    if previousId ~= nil then
      for i, item in ipairs(visible) do
        if item.id == previousId then selected = i break end
      end
    end
  else
    items = {}
    visible = {}
  end
end

local function copyField(key)
  if saving or detail == nil then return end
  call({ "copy", detail.id, key }, function(data)
    if type(data) ~= "table" or type(data.value) ~= "string" or data.value == "" then return end
    -- No secret is stored in plugin persistent state or printed to a process argument.
    noctalia.copyToClipboard(data.value, "text/plain;charset=utf-8")
    noctalia.state.set("clipboard_request", { value = data.value })
    noctalia.notify("Bitwarden", "Copied to clipboard")
  end)
end

local function openWebsite(value)
  if type(value) ~= "string" then return end
  local url = noctalia.string.trim(value)
  if url == "" or url:find("[%s%c]") then return end
  if not url:match("^https?://") then
    if url:find(":") or not url:find("%.") then
      setError("Unsupported website address")
      render()
      return
    end
    url = "https://" .. url
  end
  -- xdg-open is executed directly; the URL is never interpolated into a shell.
  if not noctalia.runAsync({ "xdg-open", url }) then
    setError("Could not open browser")
    render()
    return
  end
  panel.close()
end

local function revealField(field)
  if mode ~= "detail" or detail == nil or field == nil or not field.hidden or saving then return end
  local id = detail.id
  local key = field.key
  if revealedFields[key] ~= nil then
    revealedFields[key] = nil
    render()
    return
  end
  call({ "reveal", id, key }, function(data)
    if mode ~= "detail" or detail == nil or detail.id ~= id or entryRows[selectedField] == nil
      or entryRows[selectedField].key ~= key then return end
    if type(data) == "table" and type(data.value) == "string" then
      revealedFields[key] = data.value
      if key == "totp" then
        local now = noctalia.nowMs()
        nextTotpRefresh = now - (now % 30000) + 30000
      end
    end
  end)
end

local function activateField(field)
  if field == nil then return end
  if field.key:sub(1, 4) == "uri:" then
    openWebsite(field.value)
  else
    copyField(field.key)
  end
end

local function autotype()
  if saving or mode ~= "detail" or detail == nil or not detail.canAutotype then return end
  local id = detail.id
  -- Deliberate action: close the panel before typing into the previous window.
  local argv = { "python3", backend, "autotype", id }
  noctalia.runAsync(argv)
  panel.close()
end

local function back()
  if saving then return end
  if mode == "edit" or mode == "create" then
    mode = if mode == "create" then "search" else "detail"
    draft = nil
    draftInitial = nil
    draftChanged = false
  elseif mode == "detail" then
    revealedFields = {}
    nextTotpRefresh = 0
    totpRefreshPending = false
    mode = "search"
    detail = nil
    entryRows = {}
    selectedItem = nil
    searchKey += 1  -- focus search again
  elseif mode == "search" then
    panel.close()
    return
  end
  render()
end

local function startEdit()
  if busy or detail == nil or detail.editable ~= true then return end
  revealedFields = {}
  nextTotpRefresh = 0
  totpRefreshPending = false
  draft = {}
  local source = detail.edit or {}
  for key, value in pairs(source) do
    if key == "custom" then
      draft.custom = {}
      for i, entry in ipairs(value) do
        draft.custom[i] = { index = entry.index, name = entry.name, type = entry.type, value = entry.value }
      end
    else
      draft[key] = value
    end
  end
  draftInitial = noctalia.json.encode(draft)
  draftChanged = false
  editKey += 1
  editFocus = 1
  editFocusSerial = 0
  mode = "edit"
  render()
end

local function save()
  if busy or draft == nil then return end
  if noctalia.string.trim(draft.name or "") == "" then
    setError("Name cannot be empty")
    render()
    return
  end
  local payload
  local action
  if mode == "edit" then
    if detail == nil then return end
    action = { "edit", detail.id }
    local changes = { name = draft.name, notes = draft.notes }
    if detail.type == 1 then
      changes.username = draft.username
      changes.url = draft.url
      -- An empty password means unchanged, not deletion.
      if type(draft.password) == "string" and draft.password ~= "" then
        changes.password = draft.password
      end
    end
    changes.custom = {}
    for _, f in ipairs(draft.custom or {}) do
      if f.type == 3 then
        table.insert(changes.custom, { index = f.index, name = f.name })
      elseif f.type == 1 then
        local change = { index = f.index, name = f.name }
        if f.value ~= "" then change.value = f.value end
        table.insert(changes.custom, change)
      else
        table.insert(changes.custom, { index = f.index, name = f.name, value = f.value })
      end
    end
    payload = { revision = detail.revision, changes = changes }
  else
    action = { "create" }
    payload = { type = createType, name = draft.name, notes = draft.notes }
    if createType == 1 then
      payload.username = draft.username
      payload.password = draft.password
      payload.url = draft.url
    end
  end
  if not writeRequest(payload) then
    setError("Could not store private edit request")
    render()
    return
  end
  local wasEdit = mode == "edit"
  local before = detail
  local previousDraft = draft
  saving = true
  -- Transition directly to details; do not show the search page or reload the vault.
  -- An unsaved draft is retained until the server confirms, so failure can return
  -- to the editor without losing what was typed.
  mode = "detail"
  if wasEdit and detail ~= nil then
    local shown = {}
    for k, v in pairs(detail) do shown[k] = v end
    shown.name = draft.name
    detail = shown
  else
    detail = nil
  end
  render()
  call(action, function(data)
    saving = false
    draft = nil
    draftInitial = nil
    draftChanged = false
    detail = data.detail
    revealedFields = {}
    nextTotpRefresh = 0
    totpRefreshPending = false
    selectedItem = detail.id
    entryRows = detail.rows or {}
    selectedField = if #entryRows > 0 then 1 else 0
    local summary = data.summary
    if type(summary) == "table" then
      local replaced = false
      for i, item in ipairs(items) do
        if item.id == summary.id then
          items[i] = summary
          replaced = true
          break
        end
      end
      if not replaced then table.insert(items, summary) end
      table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
      filterItems()
      local found = false
      for i, item in ipairs(visible) do
        if item.id == summary.id then
          selected = i
          found = true
          break
        end
      end
      if not found then
        query = summary.name or ""
        searchKey += 1
        filterItems()
      end
    end
  end, true, function()
    saving = false
    -- Restore the editor and all user input if the server rejected the write.
    mode = if wasEdit then "edit" else "create"
    detail = before
    draft = previousDraft
    editKey += 1
  end)

end

local function lock()
  if busy then return end
  call({ "lock" }, function(_data)
    vault = "locked"
    mode = "search"
    items = {}
    visible = {}
    detail = nil
    revealedFields = {}
    nextTotpRefresh = 0
    totpRefreshPending = false
    draft = nil
    query = ""
    searchKey += 1
    noctalia.state.set("vault_ready", false)
    noctalia.state.set("vault_initial_items", {})
    panel.close()
  end, true)
end

local function sync()
  if busy then return end
  call({ "sync" }, function(entries)
    items = entries or {}
    filterItems()
    noctalia.notify("Bitwarden", "Vault synced")
  end, true)
end

local function header()
  local title = if mode == "detail" or mode == "edit" then (if detail then shorten(detail.name or "Item", 36) else "Item") else "Bitwarden"
  local controls = {}
  if mode ~= "search" then
    table.insert(controls, ui.button({ glyph = "arrow-left", variant = "ghost", tooltip = "Back · Alt+H", enabled = true, onClick = back }))
  else
    table.insert(controls, ui.glyph({ name = "shield-lock", size = 20, color = "primary" }))
  end
  table.insert(controls, ui.label({ text = title, fontSize = 18, fontWeight = "bold", flexGrow = 1, maxLines = 1 }))
  if mode == "search" and vault == "unlocked" then
    table.insert(controls, ui.button({ glyph = "refresh", variant = "ghost", tooltip = "Sync", enabled = true, onClick = sync }))
    table.insert(controls, ui.button({ glyph = "lock", variant = "ghost", tooltip = "Lock vault", enabled = true, onClick = lock }))
  elseif mode == "detail" and detail ~= nil then
    if detail.canAutotype then
      table.insert(controls, ui.button({ glyph = "keyboard", variant = "ghost", tooltip = "Autotype · Ctrl+T", enabled = true, onClick = autotype }))
    end
    if detail.editable then
      table.insert(controls, ui.button({ glyph = "edit", variant = "ghost", tooltip = "Edit · Ctrl+O", enabled = true, onClick = startEdit }))
    end
  end
  table.insert(controls, ui.button({ glyph = "x", variant = "ghost", tooltip = "Close", enabled = true, onClick = function() panel.close() end }))
  return ui.row({ width = BODY_WIDTH, height = 40, align = "center", gap = 10 }, controls)
end

-- Each route has its own keyed container. The host retains nodes across
-- render calls: reusing the same unkeyed column for search/detail/editor caused
-- old scroll/layout properties to leak across routes, especially after reopen.
-- Only the panel and its root have a fixed height; the active view and its
-- scrollable region divide the remaining space using flexGrow/minHeight.
local function searchContent()
  if vault ~= "unlocked" then
    return ui.column({ key = "view-locked", width = BODY_WIDTH,
      flexGrow = 1, minHeight = 0, gap = 14, align = "center", justify = "center" }, {
      ui.glyph({ name = "lock", size = 30, color = "primary" }),
      ui.label({ text = if vault == "unauthenticated" then "Log in with bw CLI first" else "Vault locked", fontSize = 15 }),
      ui.button({ text = "Unlock", variant = "primary", onClick = function()
        noctalia.state.set("vault_ready", false)
        panel.close()
        noctalia.state.set("unlock_request", noctalia.nowMs())
      end }),
    })
  end

  local rows = {}
  for i, item in ipairs(visible) do
    local current = item
    local index = i
    local icon = nil
    if useWebsiteIcons and iconPaths[current.id] ~= nil then
      icon = ui.image({ key = "site-icon-" .. current.id, path = iconPaths[current.id],
        width = 20, height = 20, radius = 4, fit = "contain" })
    else
      icon = ui.glyph({ name = if current.type == 1 then "user" elseif current.type == 2 then "notes" elseif current.type == 3 then "credit-card" else "id", size = 18, color = "primary" })
    end
    table.insert(rows, ui.row({ key = "hit-" .. tostring(i), width = LIST_WIDTH,
      padding = 11, radius = 10, gap = 10, align = "center",
      fill = if i == selected then "primary_container" else "surface_container",
      onClick = function()
        selected = index
        loadDetail(current.id)
      end }, {
        icon,
        ui.column({ gap = 3, flexGrow = 1 }, {
          ui.label({ text = shorten(current.name, 90), fontWeight = "medium", maxLines = 1 }),
          ui.label({ text = shorten(current.subtitle or "", 90), fontSize = 12, color = "on_surface_variant", maxLines = 1 }),
        }),
        ui.glyph({ name = "chevron-right", size = 14, color = "on_surface_variant" }),
      }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No matches", color = "on_surface_variant", textAlign = "center" }))
  end

  return ui.column({ key = "view-search", width = BODY_WIDTH, flexGrow = 1,
    minHeight = 0, gap = 10, align = "stretch", justify = "start" }, {
    ui.input({ key = "search-" .. searchKey, value = query, placeholder = "Search vault…",
      focus = true, enabled = true, width = BODY_WIDTH, controlSize = "lg",
      onChange = function(value)
        query = value
        selected = 1
        filterItems()
        render()
        if fetchIcons ~= nil then fetchIcons() end
      end,
      -- onKey handles confirmation; avoid a second activation via onSubmit.
    }),
    ui.row({ key = "search-count", width = BODY_WIDTH, height = 20, align = "center" }, {
      ui.label({ text = tostring(#visible) .. " results", color = "on_surface_variant", fontSize = 12 }),
    }),
    ui.scroll({ key = "search-scroll", width = BODY_WIDTH, flexGrow = 1,
      gap = 6, align = "stretch", justify = "start",
      revealKey = "hit-" .. tostring(selected) }, rows),
  })
end

local function detailsContent()
  if detail == nil then
    return ui.column({ key = "view-detail-pending", width = BODY_WIDTH,
      flexGrow = 1, minHeight = 0, justify = "start" }, {
      ui.label({ text = if saving then "Saving changes…" else "Opening item…", color = "on_surface_variant" }),
    })
  end
  local rows = {}
  for i, field in ipairs(entryRows) do
    local current = field
    local index = i
    -- Keep the copy/open target and the eye button as siblings. Nesting the
    -- button in a clickable row risks activating the row as well (copying a
    -- password when the user only wanted to reveal it).
    local rightAction
    if current.hidden then
      local isRevealed = revealedFields[current.key] ~= nil
      rightAction = ui.button({ key = "reveal-" .. current.key,
        glyph = if isRevealed then "eye-off" else "eye",
        tooltip = if isRevealed then "Hide field" else "Reveal field",
        variant = "ghost", width = 34, height = 34, enabled = not saving,
        onClick = function()
          selectedField = index
          revealField(current)
        end })
    else
      rightAction = ui.glyph({ name = if current.key:sub(1, 4) == "uri:" then "external-link" else "copy",
        size = 17, color = "primary" })
    end
    table.insert(rows, ui.row({ key = "field-" .. tostring(i), width = LIST_WIDTH,
      padding = 8, radius = 10, gap = 8, align = "center",
      fill = if i == selectedField then "primary_container" else "surface_container" }, {
      ui.row({ key = "field-action-" .. current.key, flexGrow = 1, minWidth = 0,
        padding = 4, align = "center", onClick = function()
          selectedField = index
          activateField(current)
        end }, {
        ui.column({ gap = 4, flexGrow = 1 }, {
          ui.label({ text = current.label or "Field", color = "on_surface_variant", fontSize = 12 }),
          ui.label({ text = shorten(revealedFields[current.key] or current.value or "", 160),
            maxLines = 2, fontWeight = "medium" }),
        }),
      }),
      rightAction,
    }))
  end
  if #rows == 0 then
    table.insert(rows, ui.label({ text = "No fields", color = "on_surface_variant" }))
  end

  local children = {}
  if saving then
    table.insert(children, ui.label({ key = "saving-status", text = "Saving changes…", color = "primary", fontSize = 12 }))
  end
  table.insert(children, ui.scroll({ key = "detail-scroll", width = BODY_WIDTH,
    flexGrow = 1, gap = 7, align = "stretch", justify = "start",
    revealKey = "field-" .. tostring(selectedField) }, rows))
  return ui.column({ key = "view-detail", width = BODY_WIDTH, flexGrow = 1,
    minHeight = 0, gap = 8, align = "stretch", justify = "start" }, children)
end

local function editInput(label, name, opt)
  local options = opt or {}
  editInputs += 1
  local index = editInputs
  return ui.column({ width = EDIT_FIELD_WIDTH, gap = 5, key = "group-" .. name }, {
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant" }),
    ui.input({
      width = EDIT_FIELD_WIDTH, enabled = true,
      key = "edit-" .. editKey .. "-" .. name .. (if index == editFocus then "-focused-" .. editFocusSerial else ""),
      value = options.initial or "", placeholder = options.placeholder or "",
      password = options.password or false, multiline = options.multiline or false,
      height = if options.multiline then 105 else nil,
      focus = index == editFocus,
      onChange = function(value)
        if draft ~= nil then
          if options.customIndex ~= nil then
            draft.custom[options.customIndex][options.part] = value
          else
            draft[name] = value
          end
          draftChanged = true
        end
      end,
    }),
  })
end

local function editContent()
  if draft == nil then return ui.label({ text = "Preparing editor…" }) end
  editInputs = 0
  local fields = {
    editInput("Name", "name", { initial = draft.name or "" }),
  }
  local login = mode == "create" and createType == 1 or mode == "edit" and detail and detail.type == 1
  if login then
    table.insert(fields, editInput("Username", "username", { initial = draft.username or "" }))
    table.insert(fields, editInput("Password", "password", { password = true,
      initial = if mode == "create" then draft.password or "" else "",
      placeholder = if mode == "edit" then "Leave empty to keep current password" else "" }))
    table.insert(fields, editInput("Website", "url", { initial = draft.url or "" }))
  end
  table.insert(fields, editInput("Notes", "notes", { initial = draft.notes or "", multiline = true }))
  if mode == "edit" then
    for i, custom in ipairs(draft.custom or {}) do
      table.insert(fields, ui.separator({ spacing = 5 }))
      table.insert(fields, editInput("Field name", "custom-name-" .. i, { initial = custom.name,
        customIndex = i, part = "name" }))
      if custom.type ~= 3 then
        table.insert(fields, editInput(if custom.type == 1 then "Hidden value (blank keeps existing)" else "Field value",
          "custom-value-" .. i, { initial = custom.value, password = custom.type == 1,
          customIndex = i, part = "value" }))
      else
        table.insert(fields, ui.label({ text = "Linked value preserved", color = "on_surface_variant", fontSize = 12 }))
      end
    end
  end
  return ui.column({ key = "view-edit", width = BODY_WIDTH,
    flexGrow = 1, minHeight = 0, gap = 10, align = "stretch", justify = "start" }, {
    ui.scroll({ key = "edit-scroll-" .. editKey, width = BODY_WIDTH,
      paddingH = EDIT_SCROLL_PADDING, flexGrow = 1, gap = 12, align = "start", justify = "start" }, fields),
    ui.row({ key = "edit-actions", width = BODY_WIDTH, height = 44,
      gap = 10, justify = "end", align = "center" }, {
      ui.button({ text = "Cancel", variant = "ghost", enabled = not busy, onClick = back }),
      ui.button({ text = if mode == "create" then "Create" else "Save", glyph = "check", variant = "primary",
        enabled = not busy, onClick = save }),
    }),
  })
end

render = function()
  local parts = { header() }
  if message ~= "" then
    table.insert(parts, ui.label({ text = shorten(message, 200), color = "error", fontSize = 12, maxLines = 2 }))
  end
  if mode == "search" then
    table.insert(parts, searchContent())
  elseif mode == "detail" then
    table.insert(parts, detailsContent())
  else
    table.insert(parts, editContent())
  end
  panel.render(ui.column({ key = "vault-root", width = BODY_WIDTH, height = 560,
    gap = 9, align = "stretch", justify = "start" }, parts))
end

local function activate()
  if busy then return end
  if mode == "search" and visible[selected] ~= nil then
    loadDetail(visible[selected].id)
  elseif mode == "detail" and entryRows[selectedField] ~= nil then
    activateField(entryRows[selectedField])
  end
end

local function moveSelection(delta)
  if mode == "edit" then
    if editInputs == 0 then return end
    editFocus = math.max(1, math.min(editInputs, editFocus + delta))
    editFocusSerial += 1
    render()
    return
  end
  if mode ~= "search" and mode ~= "detail" then return end
  local total = if mode == "search" then #visible else #entryRows
  if total < 1 then return end
  if mode == "search" then
    selected = math.max(1, math.min(total, selected + delta))
    if fetchIcons ~= nil then fetchIcons() end
  else
    selectedField = math.max(1, math.min(total, selectedField + delta))
  end
  render()
end

local function navigationDirection(chord)
  if bindingMatches("down", chord) or bindingMatches("tab_next", chord) then return 1 end
  if bindingMatches("up", chord) or bindingMatches("tab_previous", chord) then return -1 end
  -- Supported fallbacks if global bindings are empty or not present in older builds.
  if chord == "down" or chord == "ctrl+n" or chord == "ctrl+j" then return 1 end
  if chord == "up" or chord == "ctrl+p" or chord == "ctrl+k" then return -1 end
  return 0
end

function onKey(chord, pressed, _repeated)
  chord = string.lower(chord)
  if pressed ~= true and pressed ~= "true" then
    if heldKey == chord then
      heldKey = nil
      panel.setNeedsFrameTick(false)
    end
    return
  end
  if chord == "alt+h" then back() return end
  if chord == "space" and mode == "detail" then revealField(entryRows[selectedField]) return end
  if (chord == "ctrl+s" or bindingMatches("save", chord)) and mode == "edit" then save() return end
  if chord == "ctrl+o" and mode == "detail" then startEdit() return end
  if chord == "ctrl+t" and mode == "detail" then autotype() return end
  if chord == "return" or chord == "kp_enter" or chord == "ctrl+m" or bindingMatches("validate", chord) then
    if mode == "search" or mode == "detail" then activate() end
    return
  end
  if busy or saving or vault ~= "unlocked" then return end
  local delta = navigationDirection(chord)
  if delta ~= 0 then
    moveSelection(delta)
    if heldKey ~= chord then
      heldKey = chord
      repeatElapsed = 0
      repeatCount = 0
      panel.setNeedsFrameTick(true)
    end
  end
end

-- Captured keys do not repeat until plugin API 57. Implement the normal delay
-- and rate via the stable frame-tick API available in Noctalia 5.4.
function onFrameTick(deltaMs)
  if heldKey == nil then return end
  repeatElapsed += math.max(0, math.min(100, tonumber(deltaMs) or 16))
  if repeatElapsed < 340 then return end
  local expected = math.floor((repeatElapsed - 340) / 65) + 1
  if expected <= repeatCount then return end
  local delta = navigationDirection(heldKey)
  if delta == 0 or busy or saving or vault ~= "unlocked" then return end
  repeatCount = expected
  moveSelection(delta)
end

-- Optional website icons are fetched out of band. No remote requests unless
-- explicitly enabled; Noctalia ui.image only accepts local files.
fetchIcons = function()
  if not useWebsiteIcons or iconsRunning or vault ~= "unlocked" or mode ~= "search" then return end
  local ids = {}
  for i, item in ipairs(visible) do
    if i > 20 then break end
    if not iconAttempted[item.id] then
      table.insert(ids, item.id)
      if #ids == 20 then break end
    end
  end
  if #ids == 0 then return end
  local argv = { "python3", iconWorker }
  for _, id in ipairs(ids) do
    iconAttempted[id] = true
    table.insert(argv, id)
  end
  iconsRunning = true
  local generation = openGeneration
  local started = noctalia.runAsync(argv, function(result)
    if generation ~= openGeneration then return end
    iconsRunning = false
    if result.exitCode == 0 and not result.timedOut then
      local data = noctalia.json.decode(result.stdout or "")
      if type(data) == "table" and type(data.icons) == "table" then
        for id, path in pairs(data.icons) do
          if type(path) == "string" and path:sub(1, #(runtimeDir .. "/icons/")) == runtimeDir .. "/icons/" then
            iconPaths[id] = path
          end
        end
      end
    end
    render()
  end, 25000)
  if not started then iconsRunning = false end
end

local function resetUnlockedState()
  mode = "search"
  query = ""
  selected = 1
  selectedItem = nil
  selectedField = 1
  detail = nil
  entryRows = {}
  revealedFields = {}
  nextTotpRefresh = 0
  totpRefreshPending = false
  draft = nil
  draftInitial = nil
  draftChanged = false
  pendingSaveRefresh = false
  openingItem = false
  saving = false
  busy = false
  searchKey += 1
end

function onOpen(_context)
  openGeneration += 1
  heldKey = nil
  panel.setNeedsFrameTick(false)
  readBindings()
  local ready = noctalia.state.get("vault_ready")
  if ready ~= true then
    -- Close immediately so only the real security-key prompt appears. Once
    -- unlocked the service opens the populated panel automatically.
    panel.close()
    noctalia.state.set("unlock_request", noctalia.nowMs())
    return
  end
  runtimeDir = noctalia.state.get("vault_runtime") or ""
  if runtimeDir == "" then
    panel.close()
    noctalia.state.set("unlock_request", noctalia.nowMs())
    return
  end
  requestPath = runtimeDir .. "/request.json"
  local epoch = tonumber(noctalia.state.get("vault_epoch")) or 0
  if epoch ~= knownEpoch then
    iconPaths = {}
    iconAttempted = {}
    resetUnlockedState()
    knownEpoch = epoch
    items = noctalia.state.get("vault_initial_items") or {}
    filterItems()
  end
  if type(items) ~= "table" then items = {} end
  useWebsiteIcons = noctalia.getConfig("website_icons") == true
  vault = "unlocked"
  busy = false
  saving = false
  message = ""
  noctalia.state.set("panel_visible", true)
  render()
  fetchIcons()
  -- Validation happens in the background. Never show a loading intermediary
  -- on a warm open, and keep the current search/detail/editor selection.
  call({ "open" }, function(data)
    if data.status == "unlocked" then
      applyOpen(data)
      if pendingSaveRefresh and selectedItem ~= nil and mode == "detail" then
        pendingSaveRefresh = false
        local id = selectedItem
        call({ "detail", id }, function(fresh)
          if selectedItem == id and mode == "detail" then
            detail = fresh
            entryRows = fresh.rows or {}
            if selectedField > #entryRows then selectedField = #entryRows end
          end
        end)
      end
    else
      vault = "locked"
      noctalia.state.set("vault_ready", false)
      panel.close()
      noctalia.state.set("unlock_request", noctalia.nowMs())
    end
  end, false)
end

function onClose()
  noctalia.state.set("panel_visible", false)
  openGeneration += 1 -- invalidate pending view callbacks
  heldKey = nil
  iconsRunning = false
  iconAttempted = {} -- an in-flight fetch may have been invalidated by this close
  panel.setNeedsFrameTick(false)
  revealedFields = {} -- hide revealed fields when closing the panel
  nextTotpRefresh = 0
  totpRefreshPending = false
  -- Preserve search text, selection, item and draft in this VM between opens.
  -- A fresh unlock epoch explicitly clears all of it in resetUnlockedState.
  if saving then pendingSaveRefresh = true end
  busy = false
  saving = false
  openingItem = false
end

-- Do not auto-hide revealed fields. The eye/Space toggle or leaving details
-- controls visibility. The TOTP *value* refreshes when a new code is due,
-- without changing the revealed state.
function update()
  if mode ~= "detail" or detail == nil or revealedFields.totp == nil
    or totpRefreshPending or noctalia.nowMs() < nextTotpRefresh then return end
  local id = detail.id
  totpRefreshPending = true
  call({ "reveal", id, "totp" }, function(data)
    totpRefreshPending = false
    if mode ~= "detail" or detail == nil or detail.id ~= id or revealedFields.totp == nil then return end
    if type(data) == "table" and type(data.value) == "string" then
      revealedFields.totp = data.value
    end
    local now = noctalia.nowMs()
    nextTotpRefresh = now - (now % 30000) + 30000
  end, false, function()
    totpRefreshPending = false
    nextTotpRefresh = noctalia.nowMs() + 5000 -- avoid retrying every tick on failure
  end)
end
