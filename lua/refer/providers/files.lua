---@class FilesProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"
local fuzzy = require "refer.fuzzy"
local frecency = require "refer.frecency"

---Escape special regex characters for fd's Rust regex engine
---@param s string
---@return string
local function escape_fd_regex(s)
    return (s:gsub("([%.%+%*%?%[%]%(%)%{%}%|%^%$\\])", "\\%1"))
end

---Build an fd-compatible regex pattern from a path query containing "/"
---Each segment is joined with [^/]*\/.*  to allow arbitrary intermediate directories
---Example: "prov/files" -> "prov[^/]*/.*files"
---         "lua/ref/init" -> "lua[^/]*/.*ref[^/]*/.*init"
---@param query string
---@return string
local function build_path_regex(query)
    local segments = vim.split(query, "/", { trimempty = true })
    local escaped = {}
    for _, seg in ipairs(segments) do
        table.insert(escaped, escape_fd_regex(seg))
    end
    return table.concat(escaped, "[^/]*/.*")
end

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

            if query:find("/", 1, true) then
                table.insert(cmd, "--full-path")
                table.insert(cmd, "--")
                table.insert(cmd, build_path_regex(query))
            else
                table.insert(cmd, "--")
                table.insert(cmd, query:sub(1, 2))
            end

            return cmd
        end,
        nil,
        vim.tbl_deep_extend("force", {
            prompt = "Files > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "open_marked",
            },
            frecency = { provider = "files", key_strategy = "filepath" },
            parser = util.parsers.file,
            on_select = function(selection, data)
                util.jump_to_location(selection, data)
                pcall(vim.api.nvim_command, 'normal! g`"')
            end,
            post_process = function(output_lines, query, active_sorter)
                local sorter = active_sorter or config.default_sorter or "lua"
                -- Convert fd relative paths to ReferItems with absolute data.filename
                local items = {}
                for _, line in ipairs(output_lines) do
                    table.insert(items, {
                        text = line,
                        data = { filename = vim.fn.fnamemodify(line, ":p") },
                    })
                end
                local matches, scores = fuzzy.filter(items, query, { sorter = sorter })
                local file_frecency = opts.frecency or {}
                if
                    sorter == "lua"
                    and file_frecency.enabled ~= false
                    and frecency.is_enabled()
                    and frecency.is_available()
                then
                    matches = frecency.reorder("files", matches, {
                        scores = scores,
                        key_strategy = "filepath",
                    })
                end
                return matches
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
                ["<CR>"] = "open_marked",
            },
        }, opts)
    )
end

---Search for current word/selection using rg/grep
---@param opts? table Options
function M.grep_word(opts)
    opts = opts or {}

    local function get_selection()
        local mode = vim.fn.mode()
        if mode == "v" or mode == "V" or mode == "\22" then
            local saved_reg = vim.fn.getreg "v"
            local saved_type = vim.fn.getregtype "v"
            vim.cmd 'noau normal! "vy'
            local selection = vim.fn.getreg "v"
            vim.fn.setreg("v", saved_reg, saved_type)
            return selection
        else
            return vim.fn.expand "<cword>"
        end
    end

    local query = get_selection()
    if not query or query == "" then
        vim.notify("Refer: No text to search", vim.log.levels.WARN)
        return
    end

    local clean_query = query:gsub("\n", " ")
    local display_query = clean_query
    if #display_query > 20 then
        display_query = display_query:sub(1, 17) .. "..."
    end

    local cmd
    if vim.fn.executable "rg" == 1 then
        cmd = { "rg", "--vimgrep", "--smart-case", "--fixed-strings", "--", query }
    else
        cmd = { "grep", "-rnH", "-F", "--", query, "." }
    end

    local picker = refer.pick(
        { "Searching..." },
        util.jump_to_location,
        vim.tbl_deep_extend("force", {
            prompt = "Grep (" .. display_query .. ") > ",
            parser = util.parsers.grep,
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "open_marked",
            },
        }, opts)
    )

    vim.system(cmd, { text = true }, function(out)
        local items = {}
        if out.code == 0 and out.stdout then
            items = vim.split(out.stdout, "\n", { trimempty = true })
        elseif out.code == 1 then
            items = { "No matches found for: " .. display_query }
        else
            items = { "Error: " .. (out.stderr or "Unknown error") }
        end

        vim.schedule(function()
            picker:set_items(items)
        end)
    end)

    return picker
end

---Open a lines picker for the current buffer
---All lines are collected synchronously and filtered interactively
---@param opts? table Options
function M.lines(opts)
    opts = opts or {}

    local bufnr = vim.api.nvim_get_current_buf()
    local raw_name = vim.api.nvim_buf_get_name(bufnr)
    local filename = (raw_name and raw_name ~= "") and util.get_relative_path(raw_name) or "[No Name]"

    local raw_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local items = {}
    for lnum, line in ipairs(raw_lines) do
        table.insert(items, filename .. ":" .. lnum .. ":1:" .. line)
    end

    return refer.pick(
        items,
        nil,
        vim.tbl_deep_extend("force", {
            prompt = "Lines > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "open_marked",
            },
            parser = util.parsers.grep,
            on_select = function(selection, data)
                if data and data.lnum then
                    vim.api.nvim_win_set_cursor(0, { data.lnum, (data.col or 1) - 1 })
                end
            end,
        }, opts)
    )
end

-- Exposed for testing (internal API, not for external use)
M._escape_fd_regex = escape_fd_regex
M._build_path_regex = build_path_regex

return M
