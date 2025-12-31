---
--- collections/view.lua - ViewSource implementation for collections domain
---
--- Node types: collection (has collection_id, is_system, is_root?), note (has note_id, collection_id)
--- Default collection (id=1) becomes root node displayed with server name.
--- Create action: "name" = note, "name/" = collection (trailing slash convention).
---

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local Input = require("nui.input")
local explorer = require("neoweaver._internal.explorer")
local collections = require("neoweaver._internal.collections")
local api = require("neoweaver._internal.api")

local M = {}

--
-- Data Loading
--

--- Build NuiTree.Node[] recursively from collections and notes data
---@param collections_data table[] Flat list of collections from API
---@param notes_by_collection table<number, table[]> Notes grouped by collection_id
---@param parent_id number|nil Parent collection ID (nil for root collections)
---@return NuiTree.Node[] Array of NuiTree nodes with domain properties
local function build_collection_nodes_recursive(collections_data, notes_by_collection, parent_id)
  local nodes = {}

  for _, collection in ipairs(collections_data) do
    if collection.parentId == parent_id then
      local children = {}

      -- Add note children first
      local collection_notes = notes_by_collection[collection.id] or {}
      for _, note in ipairs(collection_notes) do
        local note_node = NuiTree.Node({
          id = "note:" .. note.id,
          type = "note",
          name = note.title,
          icon = "󰈙",
          highlight = "String",
          note_id = note.id,
          collection_id = note.collectionId,
        })
        table.insert(children, note_node)
      end

      -- Then recursively add child collections
      local child_collections = build_collection_nodes_recursive(collections_data, notes_by_collection, collection.id)
      vim.list_extend(children, child_collections)

      -- Create collection node with children
      local collection_node = NuiTree.Node({
        id = "collection:" .. collection.id,
        type = "collection",
        name = collection.displayName,
        icon = collection.isSystem and "󰉖" or "󰉋",
        highlight = collection.isSystem and "Special" or "Directory",
        collection_id = collection.id,
        is_system = collection.isSystem or false,
      }, children)

      table.insert(nodes, collection_node)
    end
  end

  return nodes
end

--- Fetch collections and notes, build NuiTree.Node[] hierarchy
---@param callback fun(nodes: NuiTree.Node[], stats: ViewStats)
local function load_data(callback)
  collections.list_collections_with_notes({}, function(data, err)
    if err then
      vim.notify("Failed to load collections: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      callback({}, { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } })
      return
    end

    -- Handle empty collections
    if not data or not data.collections or #data.collections == 0 then
      callback({}, { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } })
      return
    end

    -- Find default collection (id=1) - this becomes our root node displayed as "server"
    local default_collection = nil
    for _, collection in ipairs(data.collections) do
      if collection.id == 1 then
        default_collection = collection
        break
      end
    end

    if not default_collection then
      vim.notify("Default collection not found", vim.log.levels.ERROR)
      callback({}, { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } })
      return
    end

    -- Build children of default collection
    -- parent_id = 1 (default collection) OR parent_id = nil (legacy top-level collections)
    local child_nodes = {}

    -- Add notes directly under default collection
    local default_notes = data.notes_by_collection and data.notes_by_collection[1] or {}
    for _, note in ipairs(default_notes) do
      local note_node = NuiTree.Node({
        id = "note:" .. note.id,
        type = "note",
        name = note.title,
        icon = "󰈙",
        highlight = "String",
        note_id = note.id,
        collection_id = note.collectionId,
      })
      table.insert(child_nodes, note_node)
    end

    -- Add child collections (parent_id = 1 or nil for legacy)
    for _, collection in ipairs(data.collections) do
      if collection.id ~= 1 and (collection.parentId == 1 or collection.parentId == nil) then
        local children = {}

        -- Add note children first
        local collection_notes = data.notes_by_collection and data.notes_by_collection[collection.id] or {}
        for _, note in ipairs(collection_notes) do
          local note_node = NuiTree.Node({
            id = "note:" .. note.id,
            type = "note",
            name = note.title,
            icon = "󰈙",
            highlight = "String",
            note_id = note.id,
            collection_id = note.collectionId,
          })
          table.insert(children, note_node)
        end

        -- Then recursively add nested collections
        local nested_collections = build_collection_nodes_recursive(data.collections, data.notes_by_collection or {}, collection.id)
        vim.list_extend(children, nested_collections)

        -- Create collection node
        local collection_node = NuiTree.Node({
          id = "collection:" .. collection.id,
          type = "collection",
          name = collection.displayName,
          icon = collection.isSystem and "󰉖" or "󰉋",
          highlight = collection.isSystem and "Special" or "Directory",
          collection_id = collection.id,
          is_system = collection.isSystem or false,
        }, children)

        table.insert(child_nodes, collection_node)
      end
    end

    -- Create root node from default collection, displayed as server name
    local servers = api.config.servers
    local current_server = api.config.current_server
    local server_name = current_server or "server"

    local root_node = NuiTree.Node({
      id = "collection:" .. default_collection.id,
      type = "collection",
      name = server_name, -- Display server name instead of "default"
      icon = "󰒋",
      highlight = "Title",
      collection_id = default_collection.id,
      is_system = true, -- Default collection is system-managed
      is_root = true, -- Mark as root for special handling if needed
    }, child_nodes)

    -- Auto-expand the root node
    root_node:expand()

    -- Count notes for stats (exclude default collection from collection count since it's the root)
    local note_count = 0
    if data.notes_by_collection then
      for _, note_list in pairs(data.notes_by_collection) do
        note_count = note_count + #note_list
      end
    end

    -- Return nodes and stats
    callback({ root_node }, {
      items = {
        { label = "Collections", count = #data.collections - 1 }, -- Exclude default collection from count
        { label = "Notes", count = note_count },
      },
    })
  end)
end

--
-- Node Rendering
--

--- Render a node for display
--- Uses domain properties (type, icon, highlight, is_default, is_system) for rendering
---@param node NuiTree.Node
---@param parent NuiTree.Node|nil
---@return NuiLine[]
local function prepare_node(node, parent)
  local line = NuiLine()

  -- Indentation (2 spaces per level)
  local indent = string.rep("  ", node:get_depth() - 1)
  line:append(indent)

  -- Expand/collapse indicator for nodes with children
  if node:has_children() then
    if node:is_expanded() then
      line:append("▾ ", "NeoTreeExpander")
    else
      line:append("▸ ", "NeoTreeExpander")
    end
  else
    line:append("  ")
  end

  -- Icon (use provided icon or empty space)
  if node.icon then
    line:append(node.icon .. " ", node.highlight or "Normal")
  end

  -- Name with highlight
  line:append(node.name, node.highlight or "Normal")

  -- Special suffix for root node (default collection displayed as server)
  if node.is_root then
    line:append(" ", "Comment")
    line:append("(default)", "Comment")
  end

  return { line }
end

--
-- Stats
--

--- Get stats for statusline
--- TODO: Track stats from last load_data call when implementing statusline
---@return ViewStats
local function get_stats()
  return { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } }
end

--
-- ViewSource Definition
--

---@type ViewSource
M.source = {
  name = "collections",
  poll_interval = 5000, -- 5 seconds (stub value for testing)
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    --- Open note (leaf nodes only - expand/collapse handled by picker)
    --- Note: select does NOT receive refresh_cb - it doesn't mutate data
    ---@param node NuiTree.Node
    select = function(node)
      if node.type == "note" then
        local notes = require("neoweaver._internal.notes")
        notes.open_note(node.note_id)
      end
      -- Other types: no-op (picker handles expand/collapse for nodes with children)
    end,

    --- Create new note or collection
    --- Trailing slash convention: "name" = note, "name/" = collection
    ---@param node NuiTree.Node
    ---@param refresh_cb function|nil Callback to refresh tree after mutation
    create = function(node, refresh_cb)
      -- Get parent collection_id from node
      -- Works for both collection nodes (node itself) and note nodes (note's parent)
      local parent_id = node.collection_id

      if not parent_id then
        vim.notify("Cannot create here", vim.log.levels.WARN)
        return
      end

      local input = Input({
        relative = "cursor",
        position = { row = 1, col = 0 },
        size = { width = 40 },
        border = {
          style = "rounded",
          text = {
            top = " Create ",
            top_align = "center",
            bottom = " name │ name/ = collection ",
            bottom_align = "left",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
      }, {
        prompt = "> ",
        on_close = function()
          -- User cancelled, do nothing
        end,
        on_submit = function(value)
          -- Trim whitespace
          value = vim.trim(value)

          if value == "" then
            return
          end

          -- Check for trailing slash
          local has_trailing_slash = value:match("/$")
          local name = value:gsub("/$", "")

          if name == "" then
            vim.notify("Name cannot be empty", vim.log.levels.WARN)
            return
          end

          if has_trailing_slash then
            -- Create collection
            collections.create_collection(name, parent_id, function(collection, err)
              if err then
                vim.notify("Failed to create collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Created collection: " .. collection.displayName, vim.log.levels.INFO)
              if refresh_cb then
                refresh_cb()
              end
            end)
          else
            -- Create note via notes domain module
            -- This opens the note buffer automatically and calls refresh_cb when done
            local notes = require("neoweaver._internal.notes")
            notes.create_note(name, parent_id, function(_note)
              if refresh_cb then
                refresh_cb()
              end
            end)
          end
        end,
      })

      input:mount()

      -- Add Esc to close in normal mode
      input:map("n", "<Esc>", function()
        input:unmount()
      end, { noremap = true })
    end,

    --- Rename collection or note
    --- System collections cannot be renamed
    ---@param node NuiTree.Node
    ---@param refresh_cb function|nil Callback to refresh tree after mutation
    rename = function(node, refresh_cb)
      -- Don't allow renaming system collections
      if node.type == "collection" and node.is_system then
        vim.notify("Cannot rename system collections", vim.log.levels.WARN)
        return
      end

      local input = Input({
        relative = "cursor",
        position = { row = 1, col = 0 },
        size = { width = 40 },
        border = {
          style = "rounded",
          text = {
            top = " Rename ",
            top_align = "center",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
      }, {
        prompt = "> ",
        default_value = node.name,
        on_close = function()
          -- User cancelled, do nothing
        end,
        on_submit = function(value)
          -- Trim whitespace
          value = vim.trim(value)

          if value == "" then
            vim.notify("Name cannot be empty", vim.log.levels.WARN)
            return
          end

          if value == node.name then
            -- No change
            return
          end

          if node.type == "collection" then
            -- Rename collection
            collections.rename_collection(node.collection_id, value, function(collection, err)
              if err then
                vim.notify("Failed to rename collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Renamed collection to: " .. collection.displayName, vim.log.levels.INFO)
              if refresh_cb then
                refresh_cb()
              end
            end)
          elseif node.type == "note" then
            -- Rename note: fetch first to get etag, then patch
            api.notes.get({ id = node.note_id }, function(get_res)
              if get_res.error then
                vim.notify("Failed to fetch note: " .. (get_res.error.message or vim.inspect(get_res.error)), vim.log.levels.ERROR)
                return
              end

              local note = get_res.data
              local etag = note.etag

              api.notes.patch({ id = node.note_id, title = value }, etag, function(patch_res)
                if patch_res.error then
                  vim.notify("Failed to rename note: " .. (patch_res.error.message or vim.inspect(patch_res.error)), vim.log.levels.ERROR)
                  return
                end
                vim.notify("Renamed note to: " .. patch_res.data.title, vim.log.levels.INFO)
                if refresh_cb then
                  refresh_cb()
                end
              end)
            end)
          end
        end,
      })

      input:mount()

      -- Add Esc to close in normal mode
      input:map("n", "<Esc>", function()
        input:unmount()
      end, { noremap = true })
    end,

    --- Delete collection or note
    --- System collections cannot be deleted
    ---@param node NuiTree.Node
    ---@param refresh_cb function|nil Callback to refresh tree after mutation
    delete = function(node, refresh_cb)
      -- Don't allow deleting system collections
      if node.type == "collection" and node.is_system then
        vim.notify("Cannot delete system collections", vim.log.levels.WARN)
        return
      end

      local entity_type = node.type == "collection" and "collection" or "note"
      local confirm_prompt = string.format("Delete %s '%s'? (y/N): ", entity_type, node.name)

      local input = Input({
        relative = "cursor",
        position = { row = 1, col = 0 },
        size = { width = math.max(40, #confirm_prompt + 6) },
        border = {
          style = "rounded",
          text = {
            top = " Delete ",
            top_align = "center",
          },
        },
        win_options = {
          winhighlight = "Normal:Normal,FloatBorder:WarningMsg",
        },
      }, {
        prompt = confirm_prompt,
        on_close = function()
          -- User cancelled, do nothing
        end,
        on_submit = function(value)
          if value ~= "y" and value ~= "Y" then
            return
          end

          if node.type == "collection" then
            -- Delete collection
            collections.delete_collection(node.collection_id, function(success, err)
              if err then
                vim.notify("Failed to delete collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Deleted collection: " .. node.name, vim.log.levels.INFO)
              if refresh_cb then
                refresh_cb()
              end
            end)
          elseif node.type == "note" then
            -- Delete note
            api.notes.delete({ id = node.note_id }, function(res)
              if res.error then
                vim.notify("Failed to delete note: " .. (res.error.message or vim.inspect(res.error)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Deleted note: " .. node.name, vim.log.levels.INFO)
              if refresh_cb then
                refresh_cb()
              end
            end)
          end
        end,
      })

      input:mount()

      -- Add Esc to close in normal mode
      input:map("n", "<Esc>", function()
        input:unmount()
      end, { noremap = true })
    end,
  },
}

-- Self-register with explorer
explorer.register_view("collections", M.source)

return M
