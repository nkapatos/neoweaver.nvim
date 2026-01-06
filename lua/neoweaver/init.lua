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
---@field opts.api? table API configuration (servers, debug_info)
---@field opts.api.servers table Server configurations (required)
---@field opts.api.debug_info? boolean Enable debug logging (default: true)
---@field opts.quicknotes? table Quicknotes configuration
---@field opts.explorer? table Explorer configuration
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
--- With multiple servers:
--- require('neoweaver').setup({
---   allow_multiple_empty_notes = true,
---   api = {
---     servers = {
---       local = { url = "http://localhost:9421", default = true },
---       remote = { url = "https://api.example.com" }
---     },
---     debug_info = true
---   },
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
