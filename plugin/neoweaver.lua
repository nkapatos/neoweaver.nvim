-- neoweaver.nvim plugin entry point
-- This file is automatically sourced by Neovim on startup
-- Commands are defined here following Neovim plugin best practices

if vim.g.loaded_neoweaver then
  return
end
vim.g.loaded_neoweaver = true

-- Helper to wrap command logic with ensure_ready
local function with_ready(fn)
  return function(opts)
    require("neoweaver").ensure_ready(function()
      fn(opts)
    end)
  end
end

-- Create commands
-- Note: The plugin must be setup via require('neoweaver').setup() before these work

-- Notes commands
vim.api.nvim_create_user_command("NeoweaverNotesList", with_ready(function()
  require("neoweaver._internal.notes").list_notes()
end), { desc = "List notes" })

vim.api.nvim_create_user_command("NeoweaverNotesOpen", with_ready(function(opts)
  local id = tonumber(opts.args)
  if id then
    require("neoweaver._internal.notes").open_note(id)
  else
    vim.notify("Usage: :NeoweaverNotesOpen <note_id>", vim.log.levels.WARN)
  end
end), { nargs = 1, desc = "Open note by ID" })

vim.api.nvim_create_user_command("NeoweaverNotesNew", with_ready(function()
  require("neoweaver._internal.notes").create_note()
end), { desc = "Create new note" })

vim.api.nvim_create_user_command("NeoweaverNotesNewWithTitle", with_ready(function()
  require("neoweaver._internal.notes").create_note_with_title()
end), { desc = "Create note with title prompt" })

vim.api.nvim_create_user_command("NeoweaverNotesTitle", with_ready(function()
  require("neoweaver._internal.notes").edit_title()
end), { desc = "Edit current note title" })

vim.api.nvim_create_user_command("NeoweaverNotesDelete", with_ready(function(opts)
  local id = tonumber(opts.args)
  if id then
    require("neoweaver._internal.notes").delete_note(id)
  else
    vim.notify("Usage: :NeoweaverNotesDelete <note_id>", vim.log.levels.WARN)
  end
end), { nargs = 1, desc = "Delete note by ID" })

vim.api.nvim_create_user_command("NeoweaverNotesMeta", with_ready(function(opts)
  local id = opts.args ~= "" and tonumber(opts.args) or nil
  require("neoweaver._internal.notes").edit_metadata(id)
end), { nargs = "?", desc = "Edit note metadata - See issue #15" })

vim.api.nvim_create_user_command("NeoweaverNotesQuick", with_ready(function()
  require("neoweaver._internal.quicknote").open()
end), { desc = "Capture a quicknote" })

vim.api.nvim_create_user_command("NeoweaverNotesQuickList", with_ready(function()
  require("neoweaver._internal.quicknote").list()
end), { desc = "List quicknotes - See issue #14" })

vim.api.nvim_create_user_command("NeoweaverNotesQuickAmend", with_ready(function()
  require("neoweaver._internal.quicknote").amend()
end), { desc = "Amend quicknote - See issue #14" })

-- API/Server commands
-- Note: NeoweaverServerUse does NOT require ensure_ready - it just changes config
vim.api.nvim_create_user_command("NeoweaverServerUse", function(opts)
  local neoweaver = require("neoweaver")
  if not neoweaver._setup_done then
    vim.notify("Neoweaver: call require('neoweaver').setup() first", vim.log.levels.ERROR)
    return
  end
  -- If already initialized, use api directly; otherwise defer
  if neoweaver._initialized then
    require("neoweaver._internal.api").set_current_server(opts.args)
  else
    -- Store for later - will be used on next ensure_ready
    vim.notify("Server will be used on next command: " .. opts.args, vim.log.levels.INFO)
    -- We need to initialize to set the server, but skip health check
    local config = require("neoweaver._internal.config")
    config.apply(neoweaver._pending_opts or {})
    local api = require("neoweaver._internal.api")
    api.setup((neoweaver._pending_opts or {}).api or {})
    api.set_current_server(opts.args)
  end
end, {
  nargs = 1,
  complete = function(ArgLead)
    local neoweaver = require("neoweaver")
    if not neoweaver._setup_done then
      return {}
    end
    -- Need to get server names from pending opts or api config
    local servers = {}
    if neoweaver._initialized then
      local api = require("neoweaver._internal.api")
      servers = api.list_server_names()
    else
      -- Parse from pending opts
      local opts = neoweaver._pending_opts or {}
      local api_opts = opts.api or {}
      for name, _ in pairs(api_opts.servers or {}) do
        if type(name) == "string" then
          table.insert(servers, name)
        end
      end
      table.sort(servers)
    end
    local matches = {}
    for _, name in ipairs(servers) do
      if name:find("^" .. vim.pesc(ArgLead)) then
        table.insert(matches, name)
      end
    end
    return matches
  end,
  desc = "Select Neoweaver server by name",
})

vim.api.nvim_create_user_command("NeoweaverToggleDebug", with_ready(function()
  require("neoweaver._internal.api").toggle_debug()
end), { desc = "Toggle debug logging" })

-- Explorer commands
vim.api.nvim_create_user_command("NeoweaverExplorer", with_ready(function(opts)
  local explorer = require("neoweaver._internal.explorer")
  local action = opts.args ~= "" and opts.args or "toggle"

  if action == "open" then
    explorer.open()
  elseif action == "close" then
    explorer.close()
  elseif action == "toggle" then
    explorer.toggle()
  elseif action == "focus" then
    explorer.focus()
  else
    vim.notify("Invalid action: " .. action .. ". Use: open, close, toggle, focus", vim.log.levels.WARN)
  end
end), {
  nargs = "?",
  complete = function()
    return { "open", "close", "toggle", "focus" }
  end,
  desc = "Neoweaver collections explorer",
})

-- Collections commands
vim.api.nvim_create_user_command("NeoweaverCollectionCreate", with_ready(function(opts)
  local collections = require("neoweaver._internal.collections")
  
  -- Parse args: name [parent_id]
  local args = vim.split(opts.args, "%s+")
  local name = args[1]
  local parent_id = args[2] and tonumber(args[2]) or nil
  
  if not name or name == "" then
    vim.notify("Usage: :NeoweaverCollectionCreate <name> [parent_id]", vim.log.levels.WARN)
    return
  end
  
  collections.create_collection(name, parent_id, function(collection, err)
    if err then
      vim.notify("Failed to create collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    vim.notify("Created collection: " .. collection.displayName, vim.log.levels.INFO)
  end)
end), { nargs = "+", desc = "Create new collection" })

vim.api.nvim_create_user_command("NeoweaverCollectionRename", with_ready(function(opts)
  local collections = require("neoweaver._internal.collections")
  
  -- Parse args: id new_name
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local id = tonumber(args[1])
  local new_name = table.concat(vim.list_slice(args, 2), " ")
  
  if not id or not new_name or new_name == "" then
    vim.notify("Usage: :NeoweaverCollectionRename <id> <new_name>", vim.log.levels.WARN)
    return
  end
  
  collections.rename_collection(id, new_name, function(collection, err)
    if err then
      vim.notify("Failed to rename collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    vim.notify("Renamed collection to: " .. collection.displayName, vim.log.levels.INFO)
  end)
end), { nargs = "+", desc = "Rename collection" })

vim.api.nvim_create_user_command("NeoweaverCollectionDelete", with_ready(function(opts)
  local collections = require("neoweaver._internal.collections")
  local id = tonumber(opts.args)
  
  if not id then
    vim.notify("Usage: :NeoweaverCollectionDelete <id>", vim.log.levels.WARN)
    return
  end
  
  -- Confirm deletion
  vim.ui.input({ prompt = "Delete collection " .. id .. "? (y/N): " }, function(confirm)
    if confirm ~= "y" and confirm ~= "Y" then
      return
    end
    
    collections.delete_collection(id, function(success, err)
      if err then
        vim.notify("Failed to delete collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
        return
      end
      vim.notify("Deleted collection", vim.log.levels.INFO)
    end)
  end)
end), { nargs = 1, desc = "Delete collection" })

-- Explorer v2 (PoC)
vim.api.nvim_create_user_command("NeoweaverExplorerV2", with_ready(function()
  require("neoweaver._internal.ui.picker.explorer_v2").toggle()
end), { desc = "Toggle explorer v2 (PoC)" })

vim.keymap.set("n", "<leader>nv", function()
  require("neoweaver").ensure_ready(function()
    require("neoweaver._internal.explorer").toggle()
  end)
end, { desc = "Toggle explorer" })

vim.api.nvim_create_user_command("NeoweaverCollectionUpdate", with_ready(function(opts)
  local collections = require("neoweaver._internal.collections")
  
  -- Parse args: id [displayName=value] [parentId=value] [description=value]
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local id = tonumber(args[1])
  
  if not id then
    vim.notify("Usage: :NeoweaverCollectionUpdate <id> [displayName=value] [parentId=value]", vim.log.levels.WARN)
    return
  end
  
  local update_opts = {}
  for i = 2, #args do
    local key, value = args[i]:match("^([^=]+)=(.+)$")
    if key == "displayName" then
      update_opts.displayName = value
    elseif key == "parentId" then
      update_opts.parentId = tonumber(value)
    elseif key == "description" then
      update_opts.description = value
    end
  end
  
  if vim.tbl_isempty(update_opts) then
    vim.notify("No update options provided", vim.log.levels.WARN)
    return
  end
  
  collections.update_collection(id, update_opts, function(collection, err)
    if err then
      vim.notify("Failed to update collection: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    vim.notify("Updated collection: " .. collection.displayName, vim.log.levels.INFO)
  end)
end), { nargs = "+", desc = "Update collection" })
