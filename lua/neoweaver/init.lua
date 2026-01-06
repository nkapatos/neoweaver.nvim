--- Neoweaver - Neovim client for MindWeaver
---
--- A plugin for managing notes via the MindWeaver server API.
--- Provides commands for creating, editing, and organizing notes directly
--- within Neovim using markdown buffers.
---
--- Requires:
--- - Neovim 0.11+
--- - plenary.nvim
--- - MindWeaver server running
---
---@module neoweaver
local M = {}

-- Lazy loading state
M._pending_opts = nil
M._setup_done = false
M._initialized = false

--- Setup the neoweaver plugin
---
--- Configures the plugin options. Actual initialization is deferred
--- until the plugin is first used (lazy loading).
---
---@param opts? table Configuration options
---@field opts.allow_multiple_empty_notes? boolean Allow multiple untitled notes (default: false)
---@field opts.metadata? table Metadata extraction configuration
---@field opts.metadata.enabled? boolean Enable .weaverc.json extraction (default: false, EXPERIMENTAL)
---@field opts.api? table API configuration (servers, debug_info)
---@field opts.api.servers table Server configurations (required)
---@field opts.api.debug_info? boolean Enable debug logging (default: true)
---@field opts.keymaps? table Keymap configuration
---@field opts.keymaps.enabled? boolean Enable default keymaps (default: false)
---
---@usage [[
--- Basic setup with local server:
--- require('neoweaver').setup({
---   api = {
---     servers = {
---       local = { url = "http://localhost:9421", default = true }
---     }
---   }
--- })
---
--- With multiple servers and keymaps:
--- require('neoweaver').setup({
---   allow_multiple_empty_notes = true,
---   api = {
---     servers = {
---       local = { url = "http://localhost:9421", default = true },
---       remote = { url = "https://api.example.com" }
---     },
---     debug_info = true
---   },
---   keymaps = {
---     enabled = true,
---     notes = {
---       list = "<leader>nl",
---       open = "<leader>no",
---       new = "<leader>nn"
---     }
---   }
--- })
---
--- EXPERIMENTAL - Enable metadata extraction from .weaverc.json:
--- require('neoweaver').setup({
---   metadata = {
---     enabled = true
---   },
---   api = {
---     servers = {
---       local = { url = "http://localhost:9421", default = true }
---     }
---   }
--- })
---]]
function M.setup(opts)
  M._pending_opts = opts or {}
  M._setup_done = true
end

--- Internal: Perform actual initialization (deferred from setup)
--- @private
local function do_init()
  local opts = M._pending_opts or {}

  -- Apply configuration
  local config = require("neoweaver._internal.config")
  config.apply(opts)

  -- Setup API layer
  local api = require("neoweaver._internal.api")
  api.setup(opts.api or {})

  -- Setup notes module
  local notes = require("neoweaver._internal.notes")
  notes.setup({
    allow_multiple_empty_notes = config.get().allow_multiple_empty_notes,
  })

  -- Load explorer and views (self-register)
  require("neoweaver._internal.explorer")
  require("neoweaver._internal.collections.view")
  require("neoweaver._internal.tags.view")

  -- Setup keymaps if enabled
  if config.get().keymaps.enabled then
    M.setup_keymaps()
  end
end

--- Ensure the plugin is ready for use
---
--- This is the single entry point for all plugin functionality.
--- On first use:
--- 1. Runs deferred initialization if needed
--- 2. Pings health endpoint of current server
--- 3. If healthy -> proceeds with on_ready callback
--- 4. If unhealthy -> shows server selector, user picks another server, retries
---
--- @param on_ready fun() Called when plugin is ready (server healthy)
--- @param on_cancel? fun() Called when user cancels server selection (optional)
function M.ensure_ready(on_ready, on_cancel)
  on_cancel = on_cancel or function() end

  -- Check if setup() was called
  if not M._setup_done then
    vim.notify("Neoweaver: call require('neoweaver').setup() first", vim.log.levels.ERROR)
    on_cancel()
    return
  end

  -- Already initialized and healthy - proceed immediately
  if M._initialized then
    on_ready()
    return
  end

  -- Run deferred initialization (modules, config, etc.)
  local init_ok, init_err = pcall(do_init)
  if not init_ok then
    vim.notify("Neoweaver init failed: " .. tostring(init_err), vim.log.levels.ERROR)
    on_cancel()
    return
  end

  -- Now check server health
  local api = require("neoweaver._internal.api")
  local server_selector = require("neoweaver._internal.server_selector")

  local function check_health(failed_server)
    local current_server = api.config.current_server

    api.health.ping(current_server, function(result)
      if result.ok then
        -- Server is healthy - mark as initialized and proceed
        M._initialized = true
        on_ready()
      else
        -- Server unhealthy - show selector
        local err_msg = result.error or "unknown error"
        vim.notify(
          string.format("Server '%s' unreachable: %s", current_server, err_msg),
          vim.log.levels.WARN
        )

        server_selector.show({
          servers = api.config.servers,
          failed_server = current_server,
          on_select = function(server_name)
            -- Switch to selected server and retry
            api.set_current_server(server_name)
            check_health(current_server)
          end,
          on_cancel = function()
            on_cancel()
          end,
        })
      end
    end)
  end

  check_health(nil)
end

--- Setup keymaps for note operations
--- @private
function M.setup_keymaps()
  local notes = require("neoweaver._internal.notes")
  local quicknote = require("neoweaver._internal.quicknote")
  local config = require("neoweaver._internal.config").get()
  local km_notes = config.keymaps.notes
  local km_quick = config.keymaps.quicknotes

  local function prompt_note_id(prompt, action)
    vim.ui.input({ prompt = prompt }, function(input)
      if input == nil or input == "" then
        return
      end

      local id = tonumber(input)
      if not id then
        vim.notify("Invalid note ID", vim.log.levels.WARN)
        return
      end

      action(id)
    end)
  end

  -- Standard notes keymaps
  -- Note: list_notes removed - use explorer with collections view instead
  if km_notes.find then
    vim.keymap.set("n", km_notes.find, function()
      M.ensure_ready(function()
        notes.find_notes()
      end)
    end, { desc = "Find notes by title" })
  end

  if km_notes.open then
    vim.keymap.set("n", km_notes.open, function()
      M.ensure_ready(function()
        prompt_note_id("Note ID:", notes.open_note)
      end)
    end, { desc = "Open note by ID" })
  end

  if km_notes.edit then
    vim.keymap.set("n", km_notes.edit, function()
      M.ensure_ready(function()
        prompt_note_id("Note ID:", notes.open_note)
      end)
    end, { desc = "Edit note by ID" })
  end

  if km_notes.title then
    vim.keymap.set("n", km_notes.title, function()
      M.ensure_ready(function()
        notes.edit_title()
      end)
    end, { desc = "Edit current note title" })
  end

  if km_notes.new then
    vim.keymap.set("n", km_notes.new, function()
      M.ensure_ready(function()
        notes.new_note()
      end)
    end, { desc = "Create new note" })
  end

  if km_notes.delete then
    vim.keymap.set("n", km_notes.delete, function()
      M.ensure_ready(function()
        prompt_note_id("Note ID to delete:", notes.delete_note)
      end)
    end, { desc = "Delete note by ID" })
  end

  if km_notes.meta then
    vim.keymap.set("n", km_notes.meta, function()
      M.ensure_ready(function()
        notes.edit_metadata()
      end)
    end, { desc = "Edit note metadata - See issue #44" })
  end

  -- Quicknotes keymaps
  if km_quick.new then
    vim.keymap.set("n", km_quick.new, function()
      M.ensure_ready(function()
        quicknote.open()
      end)
    end, { desc = "Capture quicknote" })
  end

  if km_quick.list then
    vim.keymap.set("n", km_quick.list, function()
      M.ensure_ready(function()
        quicknote.list()
      end)
    end, { desc = "List quicknotes - See issue #45" })
  end

  if km_quick.amend then
    vim.keymap.set("n", km_quick.amend, function()
      M.ensure_ready(function()
        quicknote.amend()
      end)
    end, { desc = "Amend quicknote - See issue #45" })
  end

  -- Fast access quicknotes keymaps
  if km_quick.new_fast then
    vim.keymap.set("n", km_quick.new_fast, function()
      M.ensure_ready(function()
        quicknote.open()
      end)
    end, { desc = "Capture quicknote (fast)" })
  end

  if km_quick.amend_fast then
    vim.keymap.set("n", km_quick.amend_fast, function()
      M.ensure_ready(function()
        quicknote.amend()
      end)
    end, { desc = "Amend quicknote (fast) - See issue #45" })
  end

  if km_quick.list_fast then
    vim.keymap.set("n", km_quick.list_fast, function()
      M.ensure_ready(function()
        quicknote.list()
      end)
    end, { desc = "List quicknotes (fast) - See issue #45" })
  end
end

--- Get current configuration
---
--- @return table Current configuration
function M.get_config()
  return require("neoweaver._internal.config").get()
end

--- Explorer module for browsing collections and notes
--- @return table Explorer module (lazy loaded)
function M.get_explorer()
  return require("neoweaver._internal.explorer")
end

return M
