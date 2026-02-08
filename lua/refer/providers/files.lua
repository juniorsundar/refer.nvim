---@class FilesProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"

---@type vim.SystemObj|nil Current fd job handle
local current_fd_job = nil

---@type uv.uv_timer_t|nil fd debounce timer
local fd_timer = nil

---Open file picker using fd command
---Files are loaded asynchronously after minimum query length is reached
function M.files()
    if current_fd_job then
        current_fd_job:kill(15)
        current_fd_job = nil
    end

    if fd_timer then
        fd_timer:stop()
        fd_timer:close()
        fd_timer = nil
    end

    local picker = refer.pick({}, nil, {
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
        on_change = function(query, update_ui_callback)
            M.run_async_files(query, update_ui_callback)
        end,
        on_close = function()
            if current_fd_job then
                current_fd_job:kill(15)
                current_fd_job = nil
            end
            if fd_timer then
                fd_timer:stop()
                fd_timer:close()
                fd_timer = nil
            end
        end,
    })

    picker:set_items {}
    return picker
end

---@type vim.SystemObj|nil Current grep job handle
local current_job = nil

---@type uv.uv_timer_t|nil Grep debounce timer
local grep_timer = nil

---Open live grep picker using rg command
---Results update as you type
function M.live_grep()
    return refer.pick({}, util.jump_to_location, {
        prompt = "Grep > ",
        parser = util.parsers.grep,

        on_change = function(query, update_ui_callback)
            M.run_async_grep(query, update_ui_callback)
        end,
        keymaps = {
            ["<Tab>"] = "toggle_mark",
            ["<CR>"] = "select_entry",
        },
    })
end

---Run asynchronous file search with fd
---@param query string Search query
---@param update_ui_callback fun(matches: table) Callback to update UI with results
function M.run_async_files(query, update_ui_callback)
    if fd_timer then
        fd_timer:stop()
        fd_timer:close()
        fd_timer = nil
    end

    if current_fd_job then
        current_fd_job:kill(15)
        current_fd_job = nil
    end

    if not query or #query < 2 then
        update_ui_callback {}
        return
    end

    fd_timer = vim.uv.new_timer()
    if fd_timer == nil then
        return
    end

    fd_timer:start(
        100,
        0,
        vim.schedule_wrap(function()
            fd_timer:close()
            fd_timer = nil

            local ignored_dirs = { ".git", ".jj", "node_modules", ".cache" }
            local cmd = { "fd", "-H", "--type", "f", "--color", "never" }
            for _, dir in ipairs(ignored_dirs) do
                table.insert(cmd, "--exclude")
                table.insert(cmd, dir)
            end
            table.insert(cmd, "--")
            table.insert(cmd, query:sub(1, 2))

            local output_lines = {}
            local this_job

            this_job = vim.system(cmd, {
                text = true,
                stdout = function(_, data)
                    if data then
                        local lines = vim.split(data, "\n", { trimempty = true })
                        for _, line in ipairs(lines) do
                            table.insert(output_lines, line)
                        end

                        vim.schedule(function()
                            if current_fd_job ~= this_job then
                                return
                            end
                            local matches = fuzzy.filter(output_lines, query, { sorter = "lua" })
                            update_ui_callback(matches)
                        end)
                    end
                end,
            })
            current_fd_job = this_job
        end)
    )
end

---Run asynchronous grep with debouncing
---@param query string Search query
---@param update_ui_callback fun(matches: table) Callback to update UI with results
function M.run_async_grep(query, update_ui_callback)
    if grep_timer then
        grep_timer:stop()
        grep_timer:close()
        grep_timer = nil
    end

    if current_job then
        current_job:kill(15)
        current_job = nil
    end

    if not query or #query < 2 then
        update_ui_callback {}
        return
    end

    grep_timer = vim.uv.new_timer()
    if grep_timer == nil then
        return
    end

    grep_timer:start(
        100,
        0,
        vim.schedule_wrap(function()
            grep_timer:close()
            grep_timer = nil

            local cmd = { "rg", "--vimgrep", "--smart-case", "--", query }

            local output_lines = {}
            local this_job

            this_job = vim.system(cmd, {
                text = true,
                stdout = function(_, data)
                    if data then
                        local lines = vim.split(data, "\n", { trimempty = true })
                        for _, line in ipairs(lines) do
                            table.insert(output_lines, line)
                        end

                        vim.schedule(function()
                            if current_job ~= this_job then
                                return
                            end
                            update_ui_callback(output_lines)
                        end)
                    end
                end,
            })
            current_job = this_job
        end)
    )
end

return M
