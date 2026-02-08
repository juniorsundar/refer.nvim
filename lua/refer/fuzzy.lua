local M = {}

local blink = require "refer.blink"

---@alias ReferSorterFn fun(items: table, query: string): table

-- Pure Lua fuzzy scorer (fallback)
---@param str string String to score
---@param pattern string Pattern to match
---@return number|nil score Score or nil if no match
local function simple_fuzzy_score(str, pattern)
    if pattern == "" then
        return 0
    end
    local total_score = 0
    local run = 0
    local str_idx = 1
    local pat_idx = 1
    local str_len = #str
    local pat_len = #pattern
    local str_lower = str:lower()
    local pat_lower = pattern:lower()

    while pat_idx <= pat_len and str_idx <= str_len do
        local pat_char = pat_lower:sub(pat_idx, pat_idx)
        local found_idx = string.find(str_lower, pat_char, str_idx, true)

        if not found_idx then
            return nil
        end

        local distance = found_idx - str_idx
        local score = 100 - distance

        if distance == 0 then
            run = run + 10
            score = score + run
        else
            run = 0
        end

        if found_idx == 1 or str:sub(found_idx - 1, found_idx - 1):match "[^%w]" then
            score = score + 20
        end

        if found_idx > 1 and str:sub(found_idx, found_idx):match "%u" then
            score = score + 20
        end

        total_score = total_score + score
        str_idx = found_idx + 1
        pat_idx = pat_idx + 1
    end

    if pat_idx <= pat_len then
        return nil
    end
    return total_score
end

---@type table<string, ReferSorterFn> Available sorter functions
M.sorters = {
    ---Blink fuzzy sorter using Rust engine
    ---@type ReferSorterFn
    ---@return table|nil matched_indices
    blink = function(items, query)
        if not blink.is_available() then
            return nil
        end
        local _, matched_indices = blink.fuzzy(query, "refer")
        if not matched_indices then
            return {}
        end
        local matches = {}
        for _, idx in ipairs(matched_indices) do
            table.insert(matches, items[idx + 1])
        end
        return matches
    end,

    ---Mini.fuzzy sorter
    ---@type ReferSorterFn
    ---@return table|nil matched_indices
    mini = function(items, query)
        local has_mini, mini = pcall(require, "mini.fuzzy")
        if not has_mini then
            return items
        end
        local matches = mini.filtersort(query, items)
        return matches
    end,

    ---Native vim matchfuzzy sorter
    ---@type ReferSorterFn
    ---@return table|nil matched_indices
    native = function(items, query)
        if vim.fn.exists "*matchfuzzy" == 1 then
            return vim.fn.matchfuzzy(items, query)
        end
        return items
    end,

    ---Pure Lua fuzzy sorter
    ---@type ReferSorterFn
    ---@return table|nil matched_indices
    lua = function(items, query)
        local tokens = {}
        for token in query:gmatch "%S+" do
            table.insert(tokens, token)
        end

        if #tokens == 0 then
            return items
        end

        local scored = {}
        for _, item in ipairs(items) do
            local total_score = 0
            local all_tokens_match = true

            for _, token in ipairs(tokens) do
                local s = simple_fuzzy_score(item, token)
                if not s then
                    all_tokens_match = false
                    break
                end
                total_score = total_score + s
            end

            if all_tokens_match then
                table.insert(scored, { item = item, score = total_score })
            end
        end

        table.sort(scored, function(a, b)
            return a.score > b.score
        end)

        local matches = {}
        for _, entry in ipairs(scored) do
            table.insert(matches, entry.item)
        end
        return matches
    end,
}

---Register items with Blink's Rust engine if available
---@param items table List of strings
---@return boolean success Whether registration succeeded
function M.register_items(items)
    if not blink.is_available() then
        return false
    end

    local blink_items = {}
    for _, item in ipairs(items) do
        table.insert(blink_items, { label = item, sortText = item })
    end
    blink.set_provider_items("refer", blink_items)
    return true
end

---Filter items based on query
---@param items_or_provider table|fun(query: string): table List of strings or a provider function
---@param query string The search query
---@param opts table Options { sorter = function, use_blink = boolean }
---@return table matches List of matching strings
function M.filter(items_or_provider, query, opts)
    opts = opts or {}

    if type(items_or_provider) == "function" then
        return items_or_provider(query)
    end

    if query == "" then
        return items_or_provider
    end

    local sorter = opts.sorter
    if type(sorter) == "string" then
        sorter = M.sorters[sorter]
    end

    if sorter then
        return sorter(items_or_provider, query)
    end

    if opts.use_blink then
        local matches = M.sorters.blink(items_or_provider, query)
        if matches then
            return matches
        end
    end

    return M.sorters.lua(items_or_provider, query)
end

---Check if Blink fuzzy matcher is available
---@return boolean available Whether blink is available
function M.has_blink()
    return blink.is_available()
end

return M
