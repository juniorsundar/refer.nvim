---@class FilesProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"

---Open file picker using fd command
---Files are loaded asynchronously after minimum query length is reached
function M.files()
    return refer.pick_async(
        function(query)
            local ignored_dirs = { ".git", ".jj", "node_modules", ".cache" }
            local cmd = { "fd", "-H", "--type", "f", "--color", "never" }
            for _, dir in ipairs(ignored_dirs) do
                table.insert(cmd, "--exclude")
                table.insert(cmd, dir)
            end
            table.insert(cmd, "--")

            table.insert(cmd, query:sub(1, 2))
            return cmd
        end,
        nil,
        {
            prompt = "Files > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
            parser = util.parsers.file,
            on_select = function(selection, data)
                util.jump_to_location(selection, data)
                pcall(vim.api.nvim_command, 'normal! g`"')
            end,
            post_process = function(output_lines, query)
                return fuzzy.filter(output_lines, query, { sorter = "lua" })
            end,
        }
    )
end

---Open live grep picker using rg command
---Results update as you type
function M.live_grep()
    return refer.pick_async(
        function(query)
            return { "rg", "--vimgrep", "--smart-case", "--", query }
        end,
        util.jump_to_location,
        {
            prompt = "Grep > ",
            parser = util.parsers.grep,
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
        }
    )
end

return M
