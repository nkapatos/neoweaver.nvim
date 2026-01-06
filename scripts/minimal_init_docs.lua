--- Minimal Neovim environment for documentation generation (mini.doc)
--- Usage: nvim -u scripts/minimal_init_docs.lua

-- Get the project root (two levels up from scripts/)
local script_dir = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>:p")), ":h")
local project_root = vim.fs.dirname(script_dir)
local mini_path = vim.fs.joinpath(project_root, "deps", "mini.nvim")

if not vim.uv.fs_stat(mini_path) then
	error(
		"mini.nvim not found at: "
			.. mini_path
			.. "\n"
			.. "Please run: task neoweaver:deps"
	)
end

vim.opt.runtimepath:prepend(mini_path)
vim.opt.runtimepath:prepend(project_root)

print("✓ Minimal init (docs) loaded")
print("  mini.nvim: " .. mini_path)
print("  neoweaver: " .. project_root)

local minidoc = require("mini.doc")

print("\nGenerating neoweaver API documentation...")
print("Root directory: " .. project_root)

-- Generate API documentation from main module
local api_source = vim.fs.joinpath(project_root, "lua", "neoweaver", "init.lua")
local api_dest = vim.fs.joinpath(project_root, "doc", "neoweaver_api.txt")

minidoc.generate({ api_source }, api_dest)

print("✓ Generated doc/neoweaver_api.txt")
print("\nDocumentation generation complete!")
print("Run :helptags doc to generate tags for :help navigation")
