--- ViewSource for displaying notes associated with a tag
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local manager = require("neoweaver._internal.picker.manager")
local api = require("neoweaver._internal.api")

local M = {}

local function load_data(tag_id, callback)
  -- HACK: The ListNotesForTag endpoint returns the full note body.
  -- The UI should only display title and description, but for now,
  -- we have to accept the full payload until field masking is implemented.
  api.tags.list_notes_for_tag({ tagId = tag_id, pageSize = 100 }, function(res)
    if res.error then
      vim.notify("Failed to load notes for tag: " .. (res.error.message or vim.inspect(res.error)), vim.log.levels.ERROR)
      callback({}, { items = {} })
      return
    end

    local notes = res.data and res.data.notes or {}
    local nodes = {}
    for _, note in ipairs(notes) do
      table.insert(
        nodes,
        NuiTree.Node({
          id = "note:" .. note.id,
          type = "note",
          name = note.title,
          description = note.description, -- Assuming description field exists
          note_id = note.id,
          icon = "󰈙",
          highlight = "String",
        })
      )
    end

    local stats = { items = { { label = "Notes", count = #nodes } } }
    callback(nodes, stats)
  end)
end

local function prepare_node(node, _parent)
  local line = NuiLine()
  line:append("  ") -- Indent
  line:append(node.icon .. " ", node.highlight or "Normal")
  line:append(node.name, node.highlight or "Normal")

  -- if node.description then
  --   local desc_line = NuiLine()
  --   desc_line:append("    ") -- Indent description
  --   desc_line:append(node.description, "Comment")
  --   return { line, desc_line }
  -- end
  return { line }
end

local function get_stats()
  -- Stats are loaded dynamically, so this can be simple
  return { items = { { label = "Notes", count = 0 } } }
end

---@param tag_id string
---@param tag_name string
---@return ViewSource
function M.create_source(tag_id, tag_name)
  return {
    name = "notes_by_tag:" .. tag_id,
    title = "Notes for Tag: " .. tag_name,
    load_data = function(callback)
      load_data(tag_id, callback)
    end,
    prepare_node = prepare_node,
    get_stats = get_stats,
    actions = {
      select = function(node)
        if node.type == "note" then
          local notes = require("neoweaver._internal.notes")
          notes.open_note(node.note_id)
        end
      end,
    },
  }
end

return M
