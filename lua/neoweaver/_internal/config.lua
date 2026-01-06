---
--- config.lua - Configuration management for neoweaver
--- Internal module - not part of public API
---
local M = {}

M.defaults = {
  allow_multiple_empty_notes = false,
  metadata = {
    -- Metadata is automatically extracted from:
    -- - .weaveroot.json `meta` key (project-level identity)
    -- - Runtime context: project_root, cwd, commit_hash, git_branch
    -- No configuration options currently - metadata extraction is always enabled
  },
  explorer = {
    show_notifications = true, -- Show notifications on explorer refresh
  },
  quicknotes = {
    title_template = "%Y%m%d%H%M",
    collection_id = 2,
    note_type_id = 2,
    -- Note: Quicknote payload configuration - See issue #13
    popup = {
      relative = "editor",
      position = "50%",
      size = {
        width = "40%",
        height = "20%",
      },
      border = {
        style = "rounded",
        text = {
          top = "Quick Note",
          top_align = "center",
        },
      },
    },
  },

  picker = {
    size = {
      width = 60,
      height = 20,
    },
    position = "50%",
    border = {
      style = "rounded",
    },
  },
}

M.current = vim.deepcopy(M.defaults)

--- Apply user configuration options
---@param opts table User configuration options
function M.apply(opts)
  opts = opts or {}

  if opts.allow_multiple_empty_notes ~= nil then
    M.current.allow_multiple_empty_notes = opts.allow_multiple_empty_notes == true
  end

  -- Merge explorer configuration
  if opts.explorer ~= nil then
    M.current.explorer = vim.tbl_extend("force", M.current.explorer, opts.explorer)
  end

  if opts.quicknotes ~= nil then
    M.current.quicknotes = vim.tbl_deep_extend("force", M.current.quicknotes, opts.quicknotes)
  end

  -- Merge metadata configuration
  if opts.metadata ~= nil then
    M.current.metadata = vim.tbl_deep_extend("force", M.current.metadata, opts.metadata)
  end

  -- Merge picker configuration
  if opts.picker ~= nil then
    M.current.picker = vim.tbl_deep_extend("force", M.current.picker, opts.picker)
  end
end

--- Get current configuration
---@return table Current configuration
function M.get()
  return M.current
end

return M
