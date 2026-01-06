--- Configuration management for neoweaver
---@class neoweaver.Config
local M = {}

---@type neoweaver.Config
M.defaults = {
  allow_multiple_empty_notes = false,
  metadata = {},
  explorer = {
    show_notifications = true,
    position = "left", -- "left" or "right"
    size = 30,
  },
  quicknotes = { -- See issue #13
    title_template = "%Y%m%d%H%M",
    collection_id = 2,
    note_type_id = 2,
    popup = {
      relative = "editor",
      position = "50%",
      size = { width = "40%", height = "20%" },
      border = {
        style = "rounded",
        text = { top = "Quick Note", top_align = "center" },
      },
    },
  },
  picker = {
    size = { width = 60, height = 20 },
    position = "50%",
    border = { style = "rounded" },
  },
}

M.current = vim.deepcopy(M.defaults)

---@param opts neoweaver.Config
function M.apply(opts)
  opts = opts or {}

  if opts.allow_multiple_empty_notes ~= nil then
    M.current.allow_multiple_empty_notes = opts.allow_multiple_empty_notes == true
  end
  if opts.explorer then
    M.current.explorer = vim.tbl_extend("force", M.current.explorer, opts.explorer)
  end
  if opts.quicknotes then
    M.current.quicknotes = vim.tbl_deep_extend("force", M.current.quicknotes, opts.quicknotes)
  end
  if opts.metadata then
    M.current.metadata = vim.tbl_deep_extend("force", M.current.metadata, opts.metadata)
  end
  if opts.picker then
    M.current.picker = vim.tbl_deep_extend("force", M.current.picker, opts.picker)
  end
end

---@return neoweaver.Config
function M.get()
  return M.current
end

return M
