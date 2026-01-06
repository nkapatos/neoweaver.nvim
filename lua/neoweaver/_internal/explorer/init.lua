--- Sidebar host for picker views

local Split = require("nui.split")
local manager = require("neoweaver._internal.picker.manager")
local nw_config = require("neoweaver._internal.config")

local M = {}

local DEFAULT_VIEW = "collections"

local state = {
  ---@type string|nil
  current_view = nil,
  ---@type NuiSplit|nil
  split = nil,
}

local WIN_OPTIONS = {
  number = false,
  relativenumber = false,
  cursorline = true,
  signcolumn = "no",
  wrap = false,
}

local function apply_win_options()
  if state.split and state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
    for opt, val in pairs(WIN_OPTIONS) do
      vim.wo[state.split.winid][opt] = val
    end
  end
end

---@return NuiSplit
local function create_split()
  local cfg = nw_config.get().explorer
  return Split({
    relative = "editor",
    position = cfg.position,
    size = cfg.size,
    win_options = WIN_OPTIONS,
  })
end

---@param picker Picker
local function setup_host_keymaps(picker)
  if picker._host_keymaps_bound then
    return
  end

  local opts = { noremap = true, buffer = picker.bufnr }

  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)

  vim.keymap.set("n", "1", function()
    M.switch_view("collections")
  end, opts)

  vim.keymap.set("n", "2", function()
    M.switch_view("tags")
  end, opts)

  picker._host_keymaps_bound = true
end

function M.unmount()
  manager.unmount_all()

  if state.split then
    state.split:unmount()
    state.split = nil
  end

  state.current_view = nil
end

---@param view_name? string
function M.open(view_name)
  view_name = view_name or state.current_view or DEFAULT_VIEW

  local picker = manager.get_or_create_picker(view_name)
  if not picker then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  if not state.split then
    state.split = create_split()
  end

  state.split:show()

  if not state.split.winid or not vim.api.nvim_win_is_valid(state.split.winid) then
    vim.notify("Failed to open explorer window", vim.log.levels.ERROR)
    return
  end

  setup_host_keymaps(picker)

  if state.current_view and state.current_view ~= view_name then
    local current_picker = manager.get_or_create_picker(state.current_view)
    if current_picker then
      current_picker:onHide()
    end
  end

  vim.api.nvim_win_set_buf(state.split.winid, picker.bufnr)
  apply_win_options()
  state.current_view = view_name

  picker:onShow()
end

function M.close()
  if state.current_view then
    local picker = manager.get_or_create_picker(state.current_view)
    if picker then
      picker:onHide()
    end
  end

  if state.split then
    state.split:hide()
  end
end

---@param view_name? string
function M.toggle(view_name)
  if state.split and state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
    M.close()
  else
    M.open(view_name)
  end
end

---@param view_name string
function M.switch_view(view_name)
  if state.current_view == view_name and M.is_open() then
    return
  end
  M.open(view_name)
end

function M.refresh()
  if state.current_view then
    local picker = manager.get_or_create_picker(state.current_view)
    if picker then
      picker:refresh()
    end
  end
end

---@return Picker|nil
function M.get_picker()
  if state.current_view then
    return manager.get_or_create_picker(state.current_view)
  end
  return nil
end

---@return boolean
function M.is_open()
  return state.split ~= nil and state.split.winid ~= nil and vim.api.nvim_win_is_valid(state.split.winid)
end

---@return boolean
function M.is_mounted()
  return state.split ~= nil and state.split._.mounted
end

---@return "left"|"right"
function M.get_position()
  return nw_config.get().explorer.position
end

---@return number
function M.get_size()
  return nw_config.get().explorer.size
end

return M
