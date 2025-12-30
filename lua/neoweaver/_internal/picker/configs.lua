---
--- picker/configs.lua - Predefined picker configurations for different hosts
---
--- PURPOSE:
--- Provides ready-made configurations for the picker depending on where it's displayed.
--- Each config defines which keymaps are active and what actions they trigger.
---
--- CONFIGS:
--- - explorer: Full CRUD operations (create, rename, delete, select) for sidebar use
--- - floating: Minimal navigation (select, close) for floating window picker
---
--- USAGE:
--- local configs = require("neoweaver._internal.picker.configs")
--- local picker = require("neoweaver._internal.picker")
--- picker.new(source, configs.explorer)
---

local M = {}

--- Explorer sidebar config - full CRUD operations
---@type PickerConfig
M.explorer = {
  keymaps = {
    ["<CR>"] = "select",
    ["o"] = "select",
    ["a"] = "create",
    ["r"] = "rename",
    ["d"] = "delete",
  },
}

--- Floating window config - navigation only
---@type PickerConfig
M.floating = {
  keymaps = {
    ["<CR>"] = "select",
    ["q"] = "close",
    ["<Esc>"] = "close",
  },
}

return M
