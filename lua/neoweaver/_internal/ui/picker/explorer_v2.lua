---
--- explorer_v2.lua - Layout with Split container
---
--- WARNING: This module is NOT WORKING and completely unpredictable at this stage.
--- The nui.layout with Split container and floating Popups inside causes Neovim to hang.
--- Do not use until the underlying issues are resolved.
---
local Split = require("nui.split")
local Layout = require("nui.layout")
local Input = require("nui.input")
local Popup = require("nui.popup")
local NuiText = require("nui.text")
local picker = require("neoweaver._internal.ui.picker.init")

local M = {}

---@type NuiLayout|nil
local layout = nil

---@type NuiTree|nil
local tree = nil

local function create_layout()
  -- Container option A: docked split
  local sidebar = Split({
    relative = "editor",
    position = "left",
    size = 30,
  })

  -- Container option B: floating popup
  -- local container = Popup({
  --   relative = "editor",
  --   position = "50%",
  --   size = { width = 30, height = 20 },
  -- })

  local header = Popup({})
  local content = Popup({})

  layout = Layout(
    sidebar,
    Layout.Box({
      Layout.Box(header, { size = 3 }),
      Layout.Box(content, { grow = 1 }),
    }, { dir = "col" })
  )

  -- Setup header as prompt buffer
  vim.api.nvim_buf_set_option(header.bufnr, "buftype", "prompt")
  vim.fn.prompt_setprompt(header.bufnr, "> ")
  vim.fn.prompt_setcallback(header.bufnr, function(text)
    vim.notify("Submitted: " .. text)
  end)

  tree = picker.new(content.bufnr, picker.mock_items)
  tree:render()

  -- Focus content window after mount
  vim.schedule(function()
    if content.winid and vim.api.nvim_win_is_valid(content.winid) then
      vim.api.nvim_set_current_win(content.winid)
    end
  end)
end

--- Simple layout with just NuiText in both boxes (for testing navigation)
local function create_simple_layout()
  local sidebar = Split({
    relative = "editor",
    position = "left",
    size = 30,
  })

  local header = Popup({})
  local content = Popup({})

  layout = Layout(
    sidebar,
    Layout.Box({
      Layout.Box(header, { size = 3 }),
      Layout.Box(content, { grow = 1 }),
    }, { dir = "col" })
  )

  local header_text = NuiText("Header text")
  header_text:render(header.bufnr, -1, 1, 0)

  local content_text = NuiText("Content text")
  content_text:render(content.bufnr, -1, 1, 0)
end

-- function M.toggle()
--   if not layout then
--     create_layout()
--     layout:mount()
--     return
--   end
--
--   if layout._.mounted then
--     layout:hide()
--   else
--     layout:show()
--   end
-- end

--- Toggle simple layout (for testing)
function M.toggle()
  if not layout then
    create_simple_layout()
    layout:mount()
    return
  end

  if layout._.mounted then
    layout:hide()
  else
    layout:show()
  end
end

function M.unmount()
  if layout then
    layout:unmount()
    layout = nil
    tree = nil
  end
end

return M
