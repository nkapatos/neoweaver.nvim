--- Collection management - listing, creation, deletion, hierarchy
local api = require("neoweaver._internal.api")

local M = {}

---@param opts? { pageSize?: number, pageToken?: string }
---@param cb fun(collections: table[]|nil, error: table|nil)
function M.list_collections(opts, cb)
  opts = opts or {}

  ---@type mind.v3.ListCollectionsRequest
  local req = {
    pageSize = opts.pageSize or 50,
    pageToken = opts.pageToken or "",
  }

  api.collections.list(req, function(res)
    if res.error then
      cb(nil, res.error)
      return
    end

    ---@type mind.v3.ListCollectionsResponse
    local list_res = res.data
    local collections = list_res.collections or {}
    -- Pagination not implemented - See issue #7
    cb(collections, nil)
  end)
end

--- List collections with note titles (two API calls: collections + notes)
---@param opts? { pageSize?: number }
---@param cb fun(data: { collections: table[], notes_by_collection: table }|nil, error: table|nil)
function M.list_collections_with_notes(opts, cb)
  opts = opts or {}

  M.list_collections(opts, function(collections, err)
    if err then
      cb(nil, err)
      return
    end

    for _, collection in ipairs(collections) do
      collection.id = tonumber(collection.id)
      collection.parentId = collection.parentId and tonumber(collection.parentId) or nil
      collection.position = collection.position and tonumber(collection.position) or nil
    end

    ---@type mind.v3.ListNotesRequest
    local notes_req = {
      pageSize = opts.pageSize or 100,
      fieldMask = "id,title,collectionId",
    }

    api.notes.list(notes_req, function(notes_res)
      if notes_res.error then
        cb(nil, notes_res.error)
        return
      end

      ---@type mind.v3.ListNotesResponse
      local notes_list = notes_res.data
      local notes = notes_list.notes or {}

      for _, note in ipairs(notes) do
        note.id = tonumber(note.id)
        note.collectionId = tonumber(note.collectionId)
      end

      -- Group notes by collection_id
      local notes_by_collection = {}
      for _, note in ipairs(notes) do
        local cid = note.collectionId
        if not notes_by_collection[cid] then
          notes_by_collection[cid] = {}
        end
        table.insert(notes_by_collection[cid], note)
      end

      -- Sort notes alphabetically by title
      for _, note_list in pairs(notes_by_collection) do
        table.sort(note_list, function(a, b)
          return a.title < b.title
        end)
      end

      cb({
        collections = collections,
        notes_by_collection = notes_by_collection,
      }, nil)
    end)
  end)
end

--- Create a new collection
---@param name string
---@param parent_id? number
---@param cb fun(collection: table|nil, error: table|nil)
function M.create_collection(name, parent_id, cb)
  ---@type mind.v3.CreateCollectionRequest
  local req = {
    displayName = name,
  }

  if parent_id then
    req.parentId = parent_id
  end

  api.collections.create(req, function(res)
    if res.error then
      cb(nil, res.error)
      return
    end

    ---@type mind.v3.Collection
    local collection = res.data
    cb(collection, nil)
  end)
end

--- Delete a collection
---@param collection_id number
---@param cb fun(success: boolean, error: table|nil)
function M.delete_collection(collection_id, cb)
  ---@type mind.v3.DeleteCollectionRequest
  local req = {
    id = collection_id,
  }

  api.collections.delete(req, function(res)
    if res.error then
      cb(false, res.error)
      return
    end

    cb(true, nil)
  end)
end

--- Update a collection (rename/move)
---@param collection_id number
---@param opts { displayName?: string, parentId?: number, description?: string, position?: number }
---@param cb fun(collection: table|nil, error: table|nil)
function M.update_collection(collection_id, opts, cb)
  api.collections.get({ id = collection_id }, function(get_res)
    if get_res.error then
      cb(nil, get_res.error)
      return
    end

    local current = get_res.data

    ---@type mind.v3.UpdateCollectionRequest
    local req = {
      id = collection_id,
      displayName = opts.displayName or current.displayName,
    }

    -- Optional fields
    if opts.parentId ~= nil then
      req.parentId = opts.parentId
    elseif current.parentId then
      req.parentId = current.parentId
    end

    if opts.description ~= nil then
      req.description = opts.description
    elseif current.description then
      req.description = current.description
    end

    if opts.position ~= nil then
      req.position = opts.position
    elseif current.position then
      req.position = current.position
    end

    api.collections.update(req, function(res)
      if res.error then
        cb(nil, res.error)
        return
      end

      ---@type mind.v3.Collection
      local collection = res.data
      cb(collection, nil)
    end)
  end)
end

--- Rename a collection (convenience wrapper around update_collection)
---@param collection_id number
---@param new_name string
---@param cb fun(collection: table|nil, error: table|nil)
function M.rename_collection(collection_id, new_name, cb)
  M.update_collection(collection_id, { displayName = new_name }, cb)
end

--- Build tree nodes from collections and notes (recursive)
---@param collections_data table[]
---@param notes_by_collection table<number, table[]>
---@param parent_id number|nil
---@return table[]
local function build_collection_nodes_recursive(collections_data, notes_by_collection, parent_id)
  local nodes = {}

  for _, collection in ipairs(collections_data) do
    if collection.parentId == parent_id then
      local children = {}

      -- Add note children first
      local collection_notes = notes_by_collection[collection.id] or {}
      for _, note in ipairs(collection_notes) do
        table.insert(children, {
          id = "note:" .. note.id,
          type = "note",
          name = note.title,
          icon = "󰈙",
          highlight = "String",
          note_id = note.id,
          collection_id = note.collectionId,
          data = note,
        })
      end

      -- Then recursively add child collections
      local child_collections = build_collection_nodes_recursive(collections_data, notes_by_collection, collection.id)
      vim.list_extend(children, child_collections)

      -- Create collection node
      local node = {
        id = "collection:" .. collection.id,
        type = "collection",
        name = collection.displayName,
        icon = collection.isSystem and "󰉖" or "󰉋",
        highlight = collection.isSystem and "Special" or "Directory",
        collection_id = collection.id,
        is_system = collection.isSystem or false,
        data = collection,
        children = children,
      }

      table.insert(nodes, node)
    end
  end

  return nodes
end

--- Build tree nodes with server root wrapper
---@param callback fun(nodes: table[]|nil, error: table|nil, stats: { collections: number, notes: number }|nil)
function M.build_tree_nodes(callback)
  M.list_collections_with_notes({}, function(data, err)
    if err then
      callback(nil, err, nil)
      return
    end

    -- Handle empty collections
    if not data or not data.collections or #data.collections == 0 then
      callback({}, nil, { collections = 0, notes = 0 })
      return
    end

    -- Build hierarchy
    local collection_nodes = build_collection_nodes_recursive(data.collections, data.notes_by_collection or {}, nil)

    -- Wrap in server node
    local api_mod = require("neoweaver._internal.api")
    local servers = api_mod.config.servers
    local current_server = api_mod.config.current_server
    local root_nodes = {}

    if current_server and servers[current_server] then
      local server_node = {
        id = "server:" .. current_server,
        type = "server",
        name = current_server,
        icon = "󰒋",
        highlight = "Title",
        server_name = current_server,
        server_url = servers[current_server].url,
        is_default = true,
        children = collection_nodes,
      }
      table.insert(root_nodes, server_node)
    else
      -- Fallback: show collections directly
      root_nodes = collection_nodes
    end

    -- Count notes
    local note_count = 0
    if data.notes_by_collection then
      for _, note_list in pairs(data.notes_by_collection) do
        note_count = note_count + #note_list
      end
    end

    -- Return nodes and stats
    callback(root_nodes, nil, {
      collections = #data.collections,
      notes = note_count,
    })
  end)
end

--- Handle collection create action
---@param node table Tree node
---@param refresh_callback fun() Callback to refresh tree after action
function M.handle_create(node, refresh_callback)
  if node.type ~= "server" and node.type ~= "collection" then
    vim.notify("Can only create collections under servers or other collections", vim.log.levels.WARN)
    return
  end

  -- parent_id: nil for server nodes, collection_id for collection nodes
  local parent_id = nil
  if node.type == "collection" then
    parent_id = node.collection_id
  end

  vim.ui.input({ prompt = "New collection name: " }, function(name)
    if not name or name == "" then
      return
    end

    M.create_collection(name, parent_id, function(collection, err)
      if err then
        vim.notify("Failed to create collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        return
      end

      vim.notify("Created collection: " .. collection.displayName, vim.log.levels.INFO)
      refresh_callback()
    end)
  end)
end

--- Handle collection rename action
---@param node table
---@param refresh_callback fun()
function M.handle_rename(node, refresh_callback)
  if node.type ~= "collection" then
    vim.notify("Can only rename collections", vim.log.levels.WARN)
    return
  end

  if node.is_system then
    vim.notify("Cannot rename system collections", vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Rename to: ", default = node.name }, function(new_name)
    if not new_name or new_name == "" or new_name == node.name then
      return
    end

    M.rename_collection(node.collection_id, new_name, function(collection, err)
      if err then
        vim.notify("Failed to rename collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        return
      end

      vim.notify("Renamed collection to: " .. collection.displayName, vim.log.levels.INFO)
      refresh_callback()
    end)
  end)
end

--- Handle collection delete action
---@param node table
---@param refresh_callback fun()
function M.handle_delete(node, refresh_callback)
  if node.type ~= "collection" then
    vim.notify("Can only delete collections", vim.log.levels.WARN)
    return
  end

  if node.is_system then
    vim.notify("Cannot delete system collections", vim.log.levels.WARN)
    return
  end

  vim.ui.input({
    prompt = "Delete collection '" .. node.name .. "'? (y/N): ",
  }, function(confirm)
    if confirm ~= "y" and confirm ~= "Y" then
      return
    end

    M.delete_collection(node.collection_id, function(_, err)
      if err then
        vim.notify("Failed to delete collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        return
      end

      vim.notify("Deleted collection: " .. node.name, vim.log.levels.INFO)
      refresh_callback()
    end)
  end)
end

function M.setup(_opts)
  -- Future: Configuration options for collections
end

return M
