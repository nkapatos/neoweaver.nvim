--- ViewSource for collections and notes
--- Create convention: "name" = note, "name/" = collection

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local Input = require("nui.input")
local manager = require("neoweaver._internal.picker.manager")
local collections = require("neoweaver._internal.collections")
local api = require("neoweaver._internal.api")
local events = require("neoweaver._internal.events")

local M = {}

local ORIGIN = "collections"

local function empty_stats()
  return { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } }
end

local function create_note_node(note)
  return NuiTree.Node({
    id = "note:" .. note.id,
    type = "note",
    name = note.title,
    icon = "󰈙",
    highlight = "String",
    note_id = note.id,
    collection_id = note.collectionId,
  })
end

local function create_collection_node(collection, children)
  return NuiTree.Node({
    id = "collection:" .. collection.id,
    type = "collection",
    name = collection.displayName,
    icon = collection.isSystem and "󰉖" or "󰉋",
    highlight = collection.isSystem and "Special" or "Directory",
    collection_id = collection.id,
    is_system = collection.isSystem or false,
  }, children)
end

-- luacheck: push ignore 631
---@param opts { title: string, prompt: string, default_value?: string, bottom_text?: string, border_highlight?: string, width?: number, on_submit: fun(value: string), on_close?: fun() }
-- luacheck: pop
local function create_input_box(opts)
  local width = opts.width or 40
  local border_text = { top = opts.title, top_align = "center" }
  if opts.bottom_text then
    border_text.bottom = opts.bottom_text
    border_text.bottom_align = "left"
  end

  local input = Input({
    relative = "cursor",
    position = { row = 1, col = 0 },
    size = { width = width },
    border = {
      style = "rounded",
      text = border_text,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:" .. (opts.border_highlight or "FloatBorder"),
    },
  }, {
    prompt = opts.prompt,
    default_value = opts.default_value,
    on_close = opts.on_close or function() end,
    on_submit = opts.on_submit,
  })

  input:mount()
  input:map("n", "<Esc>", function()
    input:unmount()
  end, { noremap = true })

  return input
end

local function build_collection_nodes_recursive(collections_data, notes_by_collection, parent_id)
  local nodes = {}

  for _, collection in ipairs(collections_data) do
    if collection.parentId == parent_id then
      local children = {}

      local collection_notes = notes_by_collection[collection.id] or {}
      for _, note in ipairs(collection_notes) do
        table.insert(children, create_note_node(note))
      end

      local child_collections = build_collection_nodes_recursive(collections_data, notes_by_collection, collection.id)
      vim.list_extend(children, child_collections)

      table.insert(nodes, create_collection_node(collection, children))
    end
  end

  return nodes
end

local function load_data(callback)
  collections.list_collections_with_notes({}, function(data, err)
    if err then
      vim.notify("Failed to load collections: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      callback({}, empty_stats())
      return
    end

    if not data or not data.collections or #data.collections == 0 then
      callback({}, empty_stats())
      return
    end

    local default_collection = nil
    for _, collection in ipairs(data.collections) do
      if collection.id == 1 then
        default_collection = collection
        break
      end
    end

    if not default_collection then
      vim.notify("Default collection not found", vim.log.levels.ERROR)
      callback({}, empty_stats())
      return
    end

    local child_nodes = {}

    local default_notes = data.notes_by_collection and data.notes_by_collection[1] or {}
    for _, note in ipairs(default_notes) do
      table.insert(child_nodes, create_note_node(note))
    end

    for _, collection in ipairs(data.collections) do
      if collection.id ~= 1 and (collection.parentId == 1 or collection.parentId == nil) then
        local children = {}

        local collection_notes = data.notes_by_collection and data.notes_by_collection[collection.id] or {}
        for _, note in ipairs(collection_notes) do
          table.insert(children, create_note_node(note))
        end

        local notes_by_coll = data.notes_by_collection or {}
        local nested_collections = build_collection_nodes_recursive(data.collections, notes_by_coll, collection.id)
        vim.list_extend(children, nested_collections)

        table.insert(child_nodes, create_collection_node(collection, children))
      end
    end

    local server_name = api.config.current_server or "server"

    local root_node = NuiTree.Node({
      id = "collection:" .. default_collection.id,
      type = "collection",
      name = server_name,
      icon = "󰒋",
      highlight = "Title",
      collection_id = default_collection.id,
      is_system = true,
      is_root = true,
    }, child_nodes)

    root_node:expand()

    local note_count = 0
    if data.notes_by_collection then
      for _, note_list in pairs(data.notes_by_collection) do
        note_count = note_count + #note_list
      end
    end

    callback({ root_node }, {
      items = {
        { label = "Collections", count = #data.collections - 1 },
        { label = "Notes", count = note_count },
      },
    })
  end)
end

local function prepare_node(node, _parent)
  local line = NuiLine()

  local indent = string.rep("  ", node:get_depth() - 1)
  line:append(indent)

  if node:has_children() then
    line:append(node:is_expanded() and "▾ " or "▸ ", "NeoTreeExpander")
  else
    line:append("  ")
  end

  if node.icon then
    line:append(node.icon .. " ", node.highlight or "Normal")
  end

  line:append(node.name, node.highlight or "Normal")

  if node.is_root then
    line:append(" ", "Comment")
    line:append("(default)", "Comment")
  end

  return { line }
end

local function get_stats()
  return empty_stats()
end

---@type ViewSource
M.source = {
  name = "collections",
  event_types = { api.events.types.NOTE, api.events.types.COLLECTION },
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    select = function(node)
      if node.type == "note" then
        local notes = require("neoweaver._internal.notes")
        notes.open_note(node.note_id)
      end
    end,

    create = function(node, refresh_cb)
      local parent_id = node.collection_id
      if not parent_id then
        vim.notify("Cannot create here", vim.log.levels.WARN)
        return
      end

      create_input_box({
        title = " Create ",
        prompt = "> ",
        bottom_text = " name │ name/ = collection ",
        on_submit = function(value)
          value = vim.trim(value)
          if value == "" then
            return
          end

          local is_collection = value:match("/$")
          local name = value:gsub("/$", "")

          if name == "" then
            vim.notify("Name cannot be empty", vim.log.levels.WARN)
            return
          end

          if is_collection then
            collections.create_collection(name, parent_id, function(collection, err)
              if err then
                vim.notify("Failed to create collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Created collection: " .. collection.displayName, vim.log.levels.INFO)

              events.emit(events.types.COLLECTION, {
                action = "created",
                collection = { id = collection.id, displayName = collection.displayName, parentId = parent_id },
              }, { origin = ORIGIN })

              if refresh_cb then
                refresh_cb()
              end
            end)
          else
            local notes = require("neoweaver._internal.notes")
            notes.create_note(name, parent_id, function(_note)
              if refresh_cb then
                refresh_cb()
              end
            end)
          end
        end,
      })
    end,

    rename = function(node, refresh_cb)
      if node.type == "collection" and node.is_system then
        vim.notify("Cannot rename system collections", vim.log.levels.WARN)
        return
      end

      create_input_box({
        title = " Rename ",
        prompt = "> ",
        default_value = node.name,
        on_submit = function(value)
          value = vim.trim(value)

          if value == "" then
            vim.notify("Name cannot be empty", vim.log.levels.WARN)
            return
          end

          if value == node.name then
            return
          end

          if node.type == "collection" then
            collections.rename_collection(node.collection_id, value, function(collection, err)
              if err then
                vim.notify("Failed to rename collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Renamed collection to: " .. collection.displayName, vim.log.levels.INFO)

              events.emit(events.types.COLLECTION, {
                action = "updated",
                collection = { id = collection.id, displayName = collection.displayName },
              }, { origin = ORIGIN })

              if refresh_cb then
                refresh_cb()
              end
            end)
          elseif node.type == "note" then
            api.notes.get({ id = node.note_id }, function(get_res)
              if get_res.error then
                local msg = "Failed to fetch note: " .. (get_res.error.message or vim.inspect(get_res.error))
                vim.notify(msg, vim.log.levels.ERROR)
                return
              end

              local note = get_res.data
              api.notes.patch({ id = node.note_id, title = value }, note.etag, function(patch_res)
                if patch_res.error then
                  local msg = "Failed to rename note: " .. (patch_res.error.message or vim.inspect(patch_res.error))
                  vim.notify(msg, vim.log.levels.ERROR)
                  return
                end
                vim.notify("Renamed note to: " .. patch_res.data.title, vim.log.levels.INFO)

                events.emit(events.types.NOTE, {
                  action = "updated",
                  note = { id = node.note_id, title = patch_res.data.title },
                }, { origin = ORIGIN })

                if refresh_cb then
                  refresh_cb()
                end
              end)
            end)
          end
        end,
      })
    end,

    delete = function(node, refresh_cb)
      if node.type == "collection" and node.is_system then
        vim.notify("Cannot delete system collections", vim.log.levels.WARN)
        return
      end

      local entity_type = node.type == "collection" and "collection" or "note"
      local confirm_prompt = string.format("Delete %s '%s'? (y/N): ", entity_type, node.name)

      create_input_box({
        title = " Delete ",
        prompt = confirm_prompt,
        width = math.max(40, #confirm_prompt + 6),
        border_highlight = "WarningMsg",
        on_submit = function(value)
          if value ~= "y" and value ~= "Y" then
            return
          end

          if node.type == "collection" then
            collections.delete_collection(node.collection_id, function(_success, err)
              if err then
                vim.notify("Failed to delete collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
                return
              end
              vim.notify("Deleted collection: " .. node.name, vim.log.levels.INFO)

              events.emit(events.types.COLLECTION, {
                action = "deleted",
                collection = { id = node.collection_id },
              }, { origin = ORIGIN })

              if refresh_cb then
                refresh_cb()
              end
            end)
          elseif node.type == "note" then
            api.notes.delete({ id = node.note_id }, function(res)
              if res.error then
                local msg = "Failed to delete note: " .. (res.error.message or vim.inspect(res.error))
                vim.notify(msg, vim.log.levels.ERROR)
                return
              end
              vim.notify("Deleted note: " .. node.name, vim.log.levels.INFO)

              events.emit(events.types.NOTE, {
                action = "deleted",
                note = { id = node.note_id },
              }, { origin = ORIGIN })

              if refresh_cb then
                refresh_cb()
              end
            end)
          end
        end,
      })
    end,
  },
}

manager.register_source("collections", M.source)

return M
