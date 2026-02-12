---@class FilesProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"

---Open file picker using fd command
---Files are loaded asynchronously after minimum query length is reached
function M.files(opts)
    opts = opts or {}
    local config = refer.get_opts(opts)

    return refer.pick_async(
        function(query)
            local find_config = config.providers.files or {}

            if type(find_config.find_command) == "function" then
                return find_config.find_command(query)
            end

            local ignored_dirs = { ".git", ".jj", "node_modules", ".cache" }
            local cmd = { "fd", "-H", "--type", "f", "--color", "never" }

            if find_config.ignored_dirs then
                ignored_dirs = find_config.ignored_dirs
            end
            if find_config.find_command then
                cmd = vim.deepcopy(find_config.find_command)
            end

            for _, dir in ipairs(ignored_dirs) do
                table.insert(cmd, "--exclude")
                table.insert(cmd, dir)
            end
            table.insert(cmd, "--")

            table.insert(cmd, query:sub(1, 2))
            return cmd
        end,
        nil,
        vim.tbl_deep_extend("force", {
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
                local sorter = "lua"
                if config.default_sorter and config.default_sorter ~= "blink" then
                    sorter = config.default_sorter
                end
                return fuzzy.filter(output_lines, query, { sorter = sorter })
            end,
        }, opts)
    )
end

---Open live grep picker using rg command
---Results update as you type
function M.live_grep(opts)
    opts = opts or {}
    local config = refer.get_opts(opts)

    return refer.pick_async(
        function(query)
            local grep_config = config.providers.grep or {}

            -- If user provided a function, delegate completely
            if type(grep_config.grep_command) == "function" then
                return grep_config.grep_command(query)
            end

            local cmd = { "rg", "--vimgrep", "--smart-case" }
            if grep_config.grep_command then
                cmd = vim.deepcopy(grep_config.grep_command)
            end
            table.insert(cmd, "--")
            table.insert(cmd, query)
            return cmd
        end,
        util.jump_to_location,
        vim.tbl_deep_extend("force", {
            prompt = "Grep > ",
            parser = util.parsers.grep,
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
        }, opts)
    )
end

return M
