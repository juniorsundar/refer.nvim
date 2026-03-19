local M = {}

local blink = require "refer.blink"
local util = require "refer.util"

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

---Register a custom sorter function
---@param name string Name of the sorter
---@param sorter_fn ReferSorterFn The sorter function
function M.register_sorter(name, sorter_fn)
    if type(name) ~= "string" or type(sorter_fn) ~= "function" then
        vim.notify(
            "Refer: Invalid sorter registration. Name must be string and sorter must be function.",
            vim.log.levels.ERROR
        )
        return
    end
    M.sorters[name] = sorter_fn
end

---Register items with Blink's Rust engine if available
---@param items table List of strings or ReferItem tables
---@return boolean success Whether registration succeeded
function M.register_items(items)
    if not blink.is_available() then
        return false
    end

    local blink_items = {}
    for _, item in ipairs(items) do
        local label = type(item) == "string" and item or item.text
        table.insert(blink_items, { label = label, sortText = label })
    end
    blink.set_provider_items("refer", blink_items)
    return true
end

---Filter items based on query
---@param items_or_provider table|fun(query: string): table List of strings/ReferItems or a provider function
---@param query string The search query
---@param opts table Options { sorter = function, use_blink = boolean }
---@return ReferItem[] matches List of matching ReferItem tables
function M.filter(items_or_provider, query, opts)
    opts = opts or {}

    if type(items_or_provider) == "function" then
        local results = items_or_provider(query)
        return util.normalize_items(results or {})
    end

    -- Normalize all inputs to ReferItem[]
    local normalized = util.normalize_items(items_or_provider)

    if query == "" then
        return normalized
    end

    -- Build text-only list for sorter scoring
    local text_items = vim.tbl_map(function(item)
        return item.text
    end, normalized)

    -- Build lookup from text back to ReferItem
    local by_text = {}
    for _, item in ipairs(normalized) do
        by_text[item.text] = item
    end

    local sorter = opts.sorter
    if type(sorter) == "string" then
        sorter = M.sorters[sorter]
    end

    local matched_texts
    if sorter then
        matched_texts = sorter(text_items, query)
    elseif opts.use_blink then
        matched_texts = M.sorters.blink(text_items, query)
        if not matched_texts then
            matched_texts = M.sorters.lua(text_items, query)
        end
    else
        matched_texts = M.sorters.lua(text_items, query)
    end

    -- Map matched text strings back to ReferItem tables
    local result = {}
    for _, text in ipairs(matched_texts) do
        local item = by_text[text]
        if item then
            table.insert(result, item)
        end
    end
    return result
end

---Check if Blink fuzzy matcher is available
---@return boolean available Whether blink is available
function M.has_blink()
    return blink.is_available()
end

-- Exposed for testing (internal API, not for external use)
M._simple_fuzzy_score = simple_fuzzy_score

return M
