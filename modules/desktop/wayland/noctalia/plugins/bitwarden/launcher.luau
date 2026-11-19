--!nonstrict
-- Bitwarden launcher /bw

local RESULT_LIMIT = 100
local SERVE_PORT = 8087
local vaultStatus = "offline"
local lastQuery = ""
local itemsCache = {}
local nameIndex = {}

local vaultItems = nil 
local isFetching = false
local fetchGeneration = 0

local function invalidateItems()
  fetchGeneration += 1
  vaultItems = nil
  itemsCache = {}
  nameIndex = {}
  isFetching = false
end

local function hint(id, title, subtitle, glyph, query)
  return { id = id or "", title = title, subtitle = subtitle, glyph = glyph or "lock", query = query }
end

local function actionRows()
  local rows = {
    hint("action:generate", "Generate Password", "Generate and copy a secure password", "password"),
    hint("action:generate-passphrase", "Generate Passphrase", "Generate and copy a secure passphrase", "align-justified"),
  }
  
  if vaultStatus == "unlocked" then
    table.insert(rows, hint("action:lock", "Lock Vault", "Lock the local Bitwarden session", "lock"))
    table.insert(rows, hint("action:sync", "Sync Vault", "Pull the latest changes from the server", "refresh"))
    table.insert(rows, hint("action:export", "Export Vault", "Save plaintext JSON backup to disk", "download"))
  elseif vaultStatus == "offline" then
    table.insert(rows, hint("action:serve", "Start Serve", "Start the local background Bitwarden API", "plug-connected"))
  end
  return rows
end

local function searchAndScore(rows, pattern, scoredTable)
  for _, row in ipairs(rows) do
    -- A title match always ranks before a match in secondary fields.
    local titleScore = noctalia.fuzzyScore(pattern, row.title or "")
    local secondaryScore = noctalia.fuzzyScore(pattern, row.searchTerms or row.subtitle or "")
    if titleScore ~= nil or secondaryScore ~= nil then
      local score = if titleScore ~= nil then 1000000 + titleScore else secondaryScore
      table.insert(scoredTable, { row = row, score = score })
    end
  end
end

local function hasText(v)
  return type(v) == "string" and v ~= ""
end

local function shellQuote(s)
  return "'" .. string.gsub(tostring(s), "'", "'\\''") .. "'"
end

local function itemHasUsername(item)
  return type(item) == "table" and type(item.login) == "table" and hasText(item.login.username)
end

local function itemHasPassword(item)
  if type(item) ~= "table" then return false end
  if type(item.login) == "table" and hasText(item.login.password) then return true end
  return item.type == 2 and hasText(item.notes)
end

local function itemHasTotp(item)
  return type(item) == "table" and type(item.login) == "table" and hasText(item.login.totp)
end

local function itemHasUri(item)
  if type(item) ~= "table" or type(item.login) ~= "table" or type(item.login.uris) ~= "table" then return false end
  for _, u in item.login.uris do
    if type(u) == "table" and hasText(u.uri) then return true end
  end
  return false
end

local function firstWebUrl(item)
  if type(item) ~= "table" or type(item.login) ~= "table" or type(item.login.uris) ~= "table" then return nil end
  for _, u in item.login.uris do
    if type(u) == "table" and hasText(u.uri) and u.match ~= 4 and u.match ~= 5 then
      local url = noctalia.string.trim(u.uri)
      if url:lower():match("^https?://[^%s]+$") then return url end
    end
  end
  return nil
end

local function subActionRows(itemId)
  local item = itemsCache[itemId]
  local rows = {
    hint("action:back", "Back to Vault", "Return to item list", "arrow-left", ""),
  }

  local unknown = item == nil

  if unknown or itemHasPassword(item) then
    table.insert(rows, hint("subaction:" .. itemId .. ":password", "Copy Password", "Copy the item password to clipboard", "key"))
  end
  if unknown or itemHasUsername(item) then
    table.insert(rows, hint("subaction:" .. itemId .. ":username", "Copy Username", "Copy the item username to clipboard", "user"))
  end
  if unknown or itemHasTotp(item) then
    table.insert(rows, hint("subaction:" .. itemId .. ":totp", "Copy TOTP", "Copy the two-factor authentication code", "shield"))
  end
  
  if item ~= nil and type(item.fields) == "table" then
    for _, f in ipairs(item.fields) do
      if type(f) == "table" and hasText(f.name) and hasText(f.value) then
        table.insert(rows, hint(
          "subaction:" .. itemId .. ":custom:" .. f.name, 
          "Copy " .. f.name, 
          "Copy custom field to clipboard", 
          "file-text"
        ))
      end
    end
  end

  if unknown or (itemHasUsername(item) and itemHasPassword(item)) then
    table.insert(rows, hint("subaction:" .. itemId .. ":autotype", "Autotype", "Type username, Tab, then password", "keyboard"))
  end
  if firstWebUrl(item) ~= nil then
    table.insert(rows, hint("subaction:" .. itemId .. ":url", "Open URL", "Open the item linked url in your browser", "link"))
  end
  if unknown or itemHasUri(item) then
    table.insert(rows, hint("subaction:" .. itemId .. ":web", "Open in Web Vault", "Open this item in your browser", "external-link"))
  end
  return rows
end

local function buildSearchTerms(item)
  local terms = {}
  if type(item.notes) == "string" and item.notes ~= "" then table.insert(terms, item.notes) end
  
  if type(item.login) == "table" then
    if type(item.login.username) == "string" and item.login.username ~= "" then table.insert(terms, item.login.username) end
    if type(item.login.uris) == "table" then
      for _, u in ipairs(item.login.uris) do
        if type(u) == "table" and type(u.uri) == "string" and u.uri ~= "" then
          table.insert(terms, u.uri)
        end
      end
    end
  end
  
  if type(item.fields) == "table" then
    for _, f in ipairs(item.fields) do
      if type(f) == "table" then
        if type(f.name) == "string" and f.name ~= "" then table.insert(terms, f.name) end
        if type(f.value) == "string" and f.value ~= "" then table.insert(terms, f.value) end
      end
    end
  end
  
  if type(item.card) == "table" then
    if type(item.card.brand) == "string" and item.card.brand ~= "" then table.insert(terms, item.card.brand) end
    if type(item.card.cardholderName) == "string" and item.card.cardholderName ~= "" then table.insert(terms, item.card.cardholderName) end
  end
  
  if type(item.identity) == "table" then
    if type(item.identity.firstName) == "string" and item.identity.firstName ~= "" then table.insert(terms, item.identity.firstName) end
    if type(item.identity.lastName) == "string" and item.identity.lastName ~= "" then table.insert(terms, item.identity.lastName) end
    if type(item.identity.email) == "string" and item.identity.email ~= "" then table.insert(terms, item.identity.email) end
  end
  
  return table.concat(terms, " ")
end

local function insertSalted(results, row, text)
  local salt = (text == "") and "empty" or text
  table.insert(results, {
    id = row.id .. "|" .. salt,
    title = row.title,
    subtitle = row.subtitle,
    glyph = row.glyph,
    query = row.query
  })
end

local function runQuery(query)
  local text = noctalia.string.trim(query)

  local navItemId = nameIndex[text]
  local subQuery = ""

  if navItemId == nil then
    local bestMatchLen = 0
    for name, id in pairs(nameIndex) do
      if text:sub(1, #name + 1) == name .. " " then
        if #name > bestMatchLen then
          bestMatchLen = #name
          navItemId = id
          subQuery = noctalia.string.trim(text:sub(#name + 2))
        end
      end
    end
  end

  if navItemId ~= nil then
    local rows = subActionRows(navItemId)
    
    if subQuery ~= "" then
      local filtered = {}
      local backRow = table.remove(rows, 1)
      local scored = {}
      
      searchAndScore(rows, subQuery, scored)
      table.sort(scored, function(a, b) return a.score > b.score end)
      
      table.insert(filtered, backRow)
      for _, s in ipairs(scored) do
        table.insert(filtered, s.row)
      end
      launcher.setResults(query, filtered)
    else
      launcher.setResults(query, rows)
    end
    return
  end

  local actions = actionRows()

  if vaultStatus ~= "unlocked" then
    local results = {}
    if text == "" then
      for _, r in ipairs(actions) do insertSalted(results, r, text) end
    else
      local scored = {}
      searchAndScore(actions, text, scored)
      table.sort(scored, function(a, b) return a.score > b.score end)
      for _, s in ipairs(scored) do insertSalted(results, s.row, text) end
    end
    launcher.setResults(query, results)
    return
  end

  if vaultItems == nil then
    local results = {}
    if text == "" then
      for _, r in ipairs(actions) do insertSalted(results, r, text) end
    else
      local scored = {}
      searchAndScore(actions, text, scored)
      table.sort(scored, function(a, b) return a.score > b.score end)
      for _, s in ipairs(scored) do insertSalted(results, s.row, text) end
    end
    insertSalted(results, hint("", "Loading Vault...", "Fetching items", "refresh"), text)
    launcher.setResults(query, results)

    if not isFetching then
      isFetching = true
      local url = `http://127.0.0.1:{SERVE_PORT}/list/object/items`
      local requestGeneration = fetchGeneration
      noctalia.http({
        method = "GET",
        url = url,
        headers = { "Accept: application/json" },
      }, function(res)
        if requestGeneration ~= fetchGeneration then return end
        isFetching = false
        if not res.ok then
          noctalia.state.set("command", { action = "ensure_serve" })
          vaultItems = nil
        else
          local decoded = noctalia.json.decode(res.body)
          if type(decoded) == "table" and decoded.success ~= false then
            local data = decoded.data
            local items = (type(data) == "table" and type(data.data) == "table") and data.data or data
            
            itemsCache = {}
            nameIndex = {}
            vaultItems = {}
            if type(items) == "table" then
              for _, item in ipairs(items) do
                if type(item) == "table" and type(item.id) == "string" and type(item.name) == "string" then
                  itemsCache[item.id] = item
                  nameIndex[item.name] = item.id
                  
                  local parts = {}
                  if type(item.login) == "table" then
                    if type(item.login.username) == "string" and item.login.username ~= "" then table.insert(parts, item.login.username) end
                    if type(item.login.uris) == "table" then
                      for _, u in ipairs(item.login.uris) do
                        if type(u) == "table" and type(u.uri) == "string" and u.uri ~= "" then
                          table.insert(parts, u.uri)
                          break
                        end
                      end
                    end
                  end
                  
                  local t = item.type
                  local glyph = "lock"
                  if t == 1 then glyph = "user"
                  elseif t == 2 then glyph = "notes"
                  elseif t == 3 then glyph = "credit-card"
                  elseif t == 4 then glyph = "id" end

                  table.insert(vaultItems, {
                    id = "item:" .. item.id,
                    title = item.name,
                    subtitle = #parts > 0 and table.concat(parts, " · ") or "Select actions",
                    glyph = glyph,
                    query = item.name .. " ",
                    searchTerms = buildSearchTerms(item)
                  })
                end
              end
            end
          else
            vaultItems = nil
          end
        end
        if lastQuery == query then runQuery(query) end
      end)
    end
    return
  end

  local results = {}
  if text == "" then
    for _, r in ipairs(actions) do insertSalted(results, r, text) end
    local count = #results
    for _, r in ipairs(vaultItems) do
      if count >= RESULT_LIMIT then break end
      insertSalted(results, r, text)
      count += 1
    end
  else
    local scored = {}
    searchAndScore(actions, text, scored)
    searchAndScore(vaultItems, text, scored)
    table.sort(scored, function(a, b) return a.score > b.score end)

    local count = 0
    for _, s in ipairs(scored) do
      insertSalted(results, s.row, text)
      count += 1
      if count >= RESULT_LIMIT then break end
    end

    if count == 0 then
      insertSalted(results, hint("", "No matches", "Try a different search term", "zoom-question"), text)
    end
  end

  launcher.setResults(query, results)
end

local function applyStatus(st)
  local nextStatus = vaultStatus
  if type(st) == "table" and type(st.vault) == "string" then
    nextStatus = st.vault
  end
  if nextStatus ~= vaultStatus then
    invalidateItems()
  end
  vaultStatus = nextStatus
  runQuery(lastQuery)
end

applyStatus(noctalia.state.get("status"))
noctalia.state.watch("status", applyStatus)
noctalia.state.watch("items_revision", function()
  invalidateItems()
  runQuery(lastQuery)
end)

function onQuery(query)
  lastQuery = query
  runQuery(query)
end

function onActivate(id)
  if type(id) ~= "string" or id == "" then return end

  local pipeIdx = id:find("|")
  if pipeIdx then
    id = id:sub(1, pipeIdx - 1)
  end

  if id:sub(1, 10) == "subaction:" then
    local rest = id:sub(11)
    local firstColon = rest:find(":")
    if firstColon then
      local itemId = rest:sub(1, firstColon - 1)
      local actionType = rest:sub(firstColon + 1)

      if actionType == "web" then
        noctalia.runAsync(`xdg-open "https://vault.bitwarden.com/#/vault?itemId={itemId}"`)
      elseif actionType == "url" then
        local url = firstWebUrl(itemsCache[itemId])
        if url ~= nil then noctalia.runAsync("xdg-open " .. shellQuote(url)) end
      elseif actionType == "autotype" then
        noctalia.state.set("command", { action = "autotype", id = itemId })
      else
        local item = itemsCache[itemId]
        noctalia.state.set("command", {
          action = "copy", id = itemId, field = actionType,
          name = if type(item) == "table" then item.name else nil,
        })
      end
    end
    return
  end

  if id == "action:lock" then
    noctalia.state.set("command", { action = "lock" })
  elseif id == "action:sync" then
    noctalia.state.set("command", { action = "sync" })
  elseif id == "action:export" then
    noctalia.state.set("command", { action = "export" })
  elseif id == "action:serve" then
    noctalia.state.set("command", { action = "ensure_serve" })
  elseif id == "action:generate" then
    noctalia.state.set("command", { action = "generate", mode = "password" })
  elseif id == "action:generate-passphrase" then
    noctalia.state.set("command", { action = "generate", mode = "passphrase" })
  end
end
