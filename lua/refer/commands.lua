local refer = require "refer"

local M = {}

local function split_words(text)
    local words = {}
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end
    return words
end

local function get_node(path)
    local node = refer.get_commands()

    for _, segment in ipairs(path) do
        if type(node) ~= "table" then
            return nil
        end
        node = node[segment]
        if node == nil then
            return nil
        end
    end

    return node
end

local function unknown(segment)
    vim.notify("Refer: Unknown subcommand: " .. segment, vim.log.levels.ERROR)
end

function M.dispatch(path, opts)
    if not path or #path == 0 then
        unknown("")
        return
    end

    local node = refer.get_commands()
    for _, segment in ipairs(path) do
        if type(node) ~= "table" then
            unknown(segment)
            return
        end

        node = node[segment]
        if node == nil then
            unknown(segment)
            return
        end
    end

    if type(node) == "function" then
        node(opts)
        return
    end

    unknown(path[#path])
end

function M.complete(arglead, cmdline, cursorpos)
    local line = cmdline:sub(1, cursorpos)
    local words = split_words(line)

    if words[1] == "Refer" then
        table.remove(words, 1)
    end

    local path = words
    if line:sub(-1):match("%s") == nil then
        path = vim.list_slice(words, 1, math.max(#words - 1, 0))
    end

    local node = get_node(path)
    if type(node) ~= "table" then
        return {}
    end

    local keys = vim.tbl_keys(node)
    table.sort(keys)

    return vim.tbl_filter(function(key)
        return key:find(arglead, 1, true) == 1
    end, keys)
end

return M
