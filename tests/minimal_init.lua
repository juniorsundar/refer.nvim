local plenary_dir = os.getenv "PLENARY_DIR" or "/tmp/plenary.nvim"
local is_installed = vim.fn.isdirectory(plenary_dir .. "/lua/plenary") == 1

if not is_installed then
    print("Cloning plenary.nvim to " .. plenary_dir)
    if vim.fn.isdirectory(plenary_dir) == 1 then
        vim.fn.delete(plenary_dir, "rf")
    end
    vim.fn.system { "git", "clone", "https://github.com/nvim-lua/plenary.nvim", plenary_dir }
end

vim.opt.rtp:append "."
vim.opt.rtp:append(plenary_dir)

vim.cmd "runtime plugin/plenary.vim"
require "plenary.busted"
