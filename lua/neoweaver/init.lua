--- Neovim client for MindWeaver
---
--- Neoweaver provides note management capabilities by communicating with
--- the MindWeaver server over the Connect RPC API. Create, edit, and
--- organize notes directly within Neovim.
---
--- Quick start: >lua
---   require('neoweaver').setup({
---     api = {
---       servers = {
---         local = { url = "http://localhost:9421", default = true },
---       },
---     },
---   })
--- <
---
--- For full documentation, see |neoweaver|.
---
---@tag neoweaver-lua-api
---@seealso |neoweaver| |neoweaver-configuration| |neoweaver-commands|

local M = {
  _pending_opts = nil,
  _setup_done = false,
  _initialized = false,
}

--- Configure the plugin. Initialization is deferred until first use.
---
---@tag neoweaver.setup()
---@param opts? neoweaver.Config Plugin configuration
---@seealso |neoweaver-configuration|
---@usage >lua
---   require('neoweaver').setup({
---     api = {
---       servers = {
---         local = { url = "http://localhost:9421", default = true },
---       },
---     },
---   })
--- <
function M.setup(opts)
  M._pending_opts = opts or {}
  M._setup_done = true
end

---@private
local function do_init()
  local opts = M._pending_opts or {}

  local config = require("neoweaver._internal.config")
  config.apply(opts)

  local api = require("neoweaver._internal.api")
  api.setup(opts.api or {})

  local notes = require("neoweaver._internal.notes")
  notes.setup({
    allow_multiple_empty_notes = config.get().allow_multiple_empty_notes,
  })

  require("neoweaver._internal.explorer")
  require("neoweaver._internal.collections.view")
  require("neoweaver._internal.tags.view")
end

--- Entry point for all plugin functionality.
--- Runs deferred init, checks server health, shows server selector if unhealthy.
---
---@tag neoweaver.ensure_ready()
---@param on_ready fun() Called when plugin is ready
---@param on_cancel? fun() Called if user cancels server selection
---@usage >lua
---   require('neoweaver').ensure_ready(function()
---     vim.cmd('NeoweaverNotesList')
---   end)
--- <
function M.ensure_ready(on_ready, on_cancel)
  on_cancel = on_cancel or function() end

  if not M._setup_done then
    vim.notify("Neoweaver: call require('neoweaver').setup() first", vim.log.levels.ERROR)
    on_cancel()
    return
  end

  if M._initialized then
    on_ready()
    return
  end

  local init_ok, init_err = pcall(do_init)
  if not init_ok then
    vim.notify("Neoweaver init failed: " .. tostring(init_err), vim.log.levels.ERROR)
    on_cancel()
    return
  end

  local api = require("neoweaver._internal.api")
  local server_selector = require("neoweaver._internal.server_selector")

  local function check_health()
    local current_server = api.config.current_server

    api.health.ping(current_server, function(result)
      if result.ok then
        M._initialized = true
        on_ready()
      else
        vim.notify(
          string.format("Server '%s' unreachable: %s", current_server, result.error or "unknown"),
          vim.log.levels.WARN
        )

        server_selector.show({
          servers = api.config.servers,
          failed_server = current_server,
          on_select = function(server_name)
            api.set_current_server(server_name)
            check_health()
          end,
          on_cancel = on_cancel,
        })
      end
    end)
  end

  check_health()
end

--- Get the current configuration.
---
---@tag neoweaver.get_config()
---@return neoweaver.Config
function M.get_config()
  return require("neoweaver._internal.config").get()
end

--- Get the explorer instance for programmatic access.
---
---@tag neoweaver.get_explorer()
---@return neoweaver.Explorer
function M.get_explorer()
  return require("neoweaver._internal.explorer")
end

return M
