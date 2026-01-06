--- Minimal Neovim environment for testing (mini.test)
--- Usage: nvim -u scripts/minimal_init_test.lua -l scripts/run_tests.lua

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

print("✓ Minimal init (test) loaded")
print("  mini.nvim: " .. mini_path)
print("  neoweaver: " .. project_root)
