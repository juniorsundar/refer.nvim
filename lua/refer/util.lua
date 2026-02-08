local M = {}

---@class Schema
---@field pattern string|string[] Lua pattern(s) to match
---@field keys string[] Keys to extract from matches
---@field types table<string, fun(val: string): any>|nil Type conversion functions

---@class SelectionData
---@field filename string File path
---@field lnum? number Line number (1-indexed)
---@field col? number Column number (1-indexed)
---@field bufnr? number Buffer number
---@field content? string Line content

---@type table<string, Schema> Predefined parsing schemas
local schemas = {
    buffer = {
        pattern = "^(%d+):%s+(.-):(%d+):(%d+)",
        keys = { "bufnr", "filename", "lnum", "col" },
        types = { bufnr = tonumber, lnum = tonumber, col = tonumber },
    },
    lsp = {
        pattern = "^(.-):(%d+):(%d+)",
        keys = { "filename", "lnum", "col" },
        types = { lnum = tonumber, col = tonumber },
    },
    grep = {
        pattern = "^(.-):(%d+):(%d+):(.*)",
        keys = { "filename", "lnum", "col", "content" },
        types = { lnum = tonumber, col = tonumber },
    },
    file = {
        pattern = "^(.*)",
        keys = { "filename" },
        types = {},
    },
}

---Check if a file is binary
---@param path string File path
---@return boolean is_binary True if file contains null bytes
function M.is_binary(path)
    local f = io.open(path, "rb")
    if not f then
        return false
    end
    local chunk = f:read(1024)
    f:close()
    return chunk and chunk:find "\0" ~= nil
end

---Complete input line with selection
---@param input string Current input
---@param selection string Selected item
---@return string completed Completed line
function M.complete_line(input, selection)
    if vim.startswith(selection, input) then
        return selection
    end

    local prefix = input:match("^(.*[%s%.%/:\\\\])" or "") or ""
    return prefix .. selection
end

---Get relative path from current working directory
---@param filename string Absolute file path
---@return string relative_path Relative path
function M.get_relative_path(filename)
    local cwd = vim.fn.getcwd()
    if not cwd:match "/$" then
        cwd = cwd .. "/"
    end
    if filename:sub(1, #cwd) == cwd then
        return filename:sub(#cwd + 1)
    end
    return filename
end

---Parse a selection string using a predefined format
---@param selection string Selection string to parse
---@param format string Format name: "file", "grep", "lsp", "buffer"
---@return SelectionData|nil data Parsed data or nil if no match
function M.parse_selection(selection, format)
    if not selection or selection == "" then
        return nil
    end

    local schema = schemas[format]
    if not schema then
        return nil
    end

    local patterns = type(schema.pattern) == "table" and schema.pattern or { schema.pattern }
    ---@cast patterns string[]
    local matches = {}

    for _, pat in ipairs(patterns) do
        matches = { selection:match(pat) }
        if #matches > 0 then
            break
        end
    end

    if #matches == 0 then
        return nil
    end

    local result = {}
    for i, key in ipairs(schema.keys) do
        local val = matches[i]
        if val then
            if schema.types and schema.types[key] then
                val = schema.types[key](val)
            end
            result[key] = val
        end
    end

    result.lnum = result.lnum or 1
    result.col = result.col or 1

    ---@type SelectionData
    local typed_result = result
    return typed_result
end

---@type table<string, fun(selection: string): SelectionData|nil> Predefined parsers
M.parsers = {
    ---Parse file selection
    ---@param selection string
    ---@return SelectionData|nil
    file = function(selection)
        return M.parse_selection(selection, "file")
    end,

    ---Parse grep selection (filename:lnum:col:content)
    ---@param selection string
    ---@return SelectionData|nil
    grep = function(selection)
        return M.parse_selection(selection, "grep")
    end,

    ---Parse LSP selection (filename:lnum:col)
    ---@param selection string
    ---@return SelectionData|nil
    lsp = function(selection)
        return M.parse_selection(selection, "lsp")
    end,

    ---Parse buffer selection (bufnr: filename:lnum:col)
    ---@param selection string
    ---@return SelectionData|nil
    buffer = function(selection)
        return M.parse_selection(selection, "buffer")
    end,
}

---Jump to a location in a file
---@param selection string Original selection string
---@param data_or_format SelectionData|string Parsed data or format name
function M.jump_to_location(selection, data_or_format)
    ---@type SelectionData|string|nil
    local data = data_or_format

    if type(data_or_format) == "string" then
        data = M.parse_selection(selection, data_or_format)
    end

    if data and data.filename then
        vim.cmd("edit " .. vim.fn.fnameescape(data.filename))

        if data.lnum and data.col then
            vim.api.nvim_win_set_cursor(0, { data.lnum, data.col - 1 })
        end
    end
end

---Get content of a specific line from a file
---@param filename string File path
---@param lnum number Line number (1-indexed)
---@return string content Line content or empty string
function M.get_line_content(filename, lnum)
    if vim.fn.filereadable(filename) == 0 then
        return ""
    end

    local bufnr = vim.fn.bufnr(filename)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        local lines = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)
        return lines[1] or ""
    end

    local lines = vim.fn.readfile(filename, "", lnum)
    return lines[lnum] or ""
end

return M
