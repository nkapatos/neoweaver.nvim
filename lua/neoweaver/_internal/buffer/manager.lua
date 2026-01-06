--- Generic buffer management - lifecycle, state tracking, bidirectional lookup
local M = {}

---@class BufferEntity
---@field type string Entity type (e.g., "note", "collection")
---@field id any Entity identifier
---@field data? table Optional entity data

---@class BufferHandlers
---@field on_save? fun(bufnr: integer, id: any) Called when buffer is saved
---@field on_close? fun(bufnr: integer, id: any) Called when buffer is closed

---@class BufferOptions
---@field type string Entity type (e.g., "note", "collection")
---@field id any Entity identifier (number, string, etc.)
---@field name? string Buffer name (optional, will use "Unnamed" if not provided)
---@field filetype? string Buffer filetype (default: "markdown")
---@field modifiable? boolean Whether buffer is modifiable (default: true)
---@field buflisted? boolean Whether buffer appears in buffer list (default: true)
---@field bufhidden? string Buffer hide behavior (default: "wipe")
---@field data? table Initial entity data to store
---@field win? number Target window ID to display buffer in (optional, will find suitable window if not provided)

-- State
M.state = {
  ---@type table<integer, BufferEntity>
  buffers = {},
  ---@type table<string, integer>
  index = {},
  ---@type table<string, BufferHandlers>
  handlers = {},
}

---@param type string
---@param id any
---@return string
local function make_key(type, id)
  return type .. ":" .. tostring(id)
end

---Find suitable window (excludes explorer, terminal, floats)
---@return number|nil
local function find_target_window()
  local current_win = vim.api.nvim_get_current_win()
  local current_buf = vim.api.nvim_win_get_buf(current_win)
  local current_buftype = vim.api.nvim_get_option_value("buftype", { buf = current_buf })
  local current_filetype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })

  if current_buftype == "" and current_filetype ~= "neoweaver_explorer" then
    return current_win
  end

  local wins = vim.api.nvim_tabpage_list_wins(0)

  table.sort(wins, function(a, b)
    local ba = vim.api.nvim_win_get_buf(a)
    local bb = vim.api.nvim_win_get_buf(b)
    local info_a = vim.fn.getbufinfo(ba)[1]
    local info_b = vim.fn.getbufinfo(bb)[1]
    return (info_a and info_a.lastused or 0) > (info_b and info_b.lastused or 0)
  end)

  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
      local win_config = vim.api.nvim_win_get_config(win)
      local is_float = win_config.relative ~= ""

      if not is_float and buftype == "" and filetype ~= "neoweaver_explorer" then
        return win
      end
    end
  end

  -- No suitable window - split from explorer if present
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
    if filetype == "neoweaver_explorer" then
      vim.api.nvim_set_current_win(win)
      vim.cmd("vsplit")
      local new_win = vim.api.nvim_get_current_win()
      return new_win
    end
  end

  return nil
end

---Register event handlers for a buffer type
---@param type string
---@param handlers BufferHandlers
function M.register_type(type, handlers)
  M.state.handlers[type] = handlers
end

---Switch to buffer in suitable window
---@param bufnr integer
function M.switch_to_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local target_win = find_target_window()
  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.api.nvim_set_current_buf(bufnr)
end

---Create a managed buffer
---@param opts BufferOptions
---@return integer
function M.create(opts)
  if not opts.type or not opts.id then
    error("buffer_manager.create: type and id are required")
  end

  local target_win = opts.win or find_target_window()

  local existing = M.get(opts.type, opts.id)
  if existing and vim.api.nvim_buf_is_valid(existing) then
    -- Buffer already exists, switch to target window and set buffer
    if target_win and vim.api.nvim_win_is_valid(target_win) then
      vim.api.nvim_set_current_win(target_win)
    end
    vim.api.nvim_set_current_buf(existing)
    return existing
  end

  local name = opts.name or "Unnamed"
  local bufnr = vim.fn.bufnr(name, true)

  local buf_opts = {
    filetype = opts.filetype or "markdown",
    buflisted = opts.buflisted ~= false, -- default true
    modifiable = opts.modifiable ~= false, -- default true
    bufhidden = opts.bufhidden or "wipe",
  }

  for opt, value in pairs(buf_opts) do
    vim.api.nvim_set_option_value(opt, value, { buf = bufnr })
  end

  local key = make_key(opts.type, opts.id)
  M.state.buffers[bufnr] = {
    type = opts.type,
    id = opts.id,
    data = opts.data or {},
  }
  M.state.index[key] = bufnr

  local handlers = M.state.handlers[opts.type]
  if handlers and handlers.on_save then
    local group = vim.api.nvim_create_augroup("NwBufWrite_" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      group = group,
      buffer = bufnr,
      callback = function()
        handlers.on_save(bufnr, opts.id)
      end,
    })
  end

  local cleanup_group = vim.api.nvim_create_augroup("NwBufCleanup_" .. bufnr, { clear = true })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = cleanup_group,
    buffer = bufnr,
    callback = function()
      if handlers and handlers.on_close then
        handlers.on_close(bufnr, opts.id)
      end

      local entity = M.state.buffers[bufnr]
      if entity then
        local cleanup_key = make_key(entity.type, entity.id)
        M.state.index[cleanup_key] = nil
        M.state.buffers[bufnr] = nil
      end
    end,
  })

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
  vim.api.nvim_set_current_buf(bufnr)

  local statusline = require("neoweaver._internal.buffer.statusline")
  local current_win = vim.api.nvim_get_current_win()
  statusline.setup(bufnr, current_win)

  return bufnr
end

---Get buffer for entity
---@param type string
---@param id any
---@return integer|nil
function M.get(type, id)
  local key = make_key(type, id)
  return M.state.index[key]
end

---Get entity from buffer (reverse lookup)
---@param bufnr integer
---@return BufferEntity|nil
function M.get_entity(bufnr)
  return M.state.buffers[bufnr]
end

---Check if buffer exists for entity
---@param type string
---@param id any
---@return boolean
function M.exists(type, id)
  local bufnr = M.get(type, id)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

---Check if buffer is managed
---@param bufnr integer
---@return boolean
function M.is_managed(bufnr)
  return M.state.buffers[bufnr] ~= nil
end

---List managed buffers (optionally by type)
---@param type? string
---@return table<integer, BufferEntity>
function M.list(type)
  if not type then
    return M.state.buffers
  end

  local filtered = {}
  for bufnr, entity in pairs(M.state.buffers) do
    if entity.type == type then
      filtered[bufnr] = entity
    end
  end
  return filtered
end

---Close a managed buffer
---@param bufnr integer
function M.close(bufnr)
  if not M.is_managed(bufnr) then
    return
  end

  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

return M
