-- Minimal init.lua for running tests and documentation generation
-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.cmd([[let &rtp.=','.getcwd()]])

-- Add dependencies to runtimepath
vim.cmd('set rtp+=deps/mini.nvim')
vim.cmd('set rtp+=deps/nui.nvim')
vim.cmd('set rtp+=deps/plenary.nvim')

-- Set up 'mini.test' only when calling headless Neovim (like with `task test`)
if #vim.api.nvim_list_uis() == 0 then
  require('mini.test').setup()
end
