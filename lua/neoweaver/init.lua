--- Neoweaver - Neovim client for MindWeaver
---@module neoweaver
local M = {
  _pending_opts = nil,
  _setup_done = false,
  _initialized = false,
}

--- Configure the plugin. Initialization is deferred until first use.
--- See docs/configuration.md for options.
---@param opts? neoweaver.Config
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

--- Single entry point for all plugin functionality.
--- Runs deferred init, checks server health, shows server selector if unhealthy.
---@param on_ready fun() Called when plugin is ready
---@param on_cancel? fun() Called when user cancels server selection
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

---@return neoweaver.Config
function M.get_config()
  return require("neoweaver._internal.config").get()
end

---@return neoweaver.Explorer
function M.get_explorer()
  return require("neoweaver._internal.explorer")
end

return M
