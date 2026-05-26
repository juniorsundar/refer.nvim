local M = {}

-- Default bucket configuration.
-- Boundaries are half-open: [0, max_age).
-- Each bucket: { max_age = number, divisor = number }.
-- Negative ages (future timestamps) are treated as bucket 0.
local DEFAULT_BUCKETS = {
    { max_age = 3600, divisor = 1 }, -- last hour
    { max_age = 86400, divisor = 2 }, -- last day
    { max_age = 604800, divisor = 4 }, -- last week
    { max_age = math.huge, divisor = 8 }, -- older
}

---Compute Mozilla-style bucketed frecency score.
---score = count / divisor where divisor depends on the age bucket.
---@param count number How many times the item was selected
---@param age number Seconds since last selection (now - last_selected_at)
---@param buckets? table[] Custom bucket configuration (defaults to DEFAULT_BUCKETS)
---@return number frecency_score
function M.compute(count, age, buckets)
    if count == 0 then
        return 0
    end

    buckets = buckets or DEFAULT_BUCKETS

    -- Negative age (future timestamps) → treat as most recent
    local effective_age = math.max(0, age)

    for _, bucket in ipairs(buckets) do
        if effective_age < bucket.max_age then
            return count / bucket.divisor
        end
    end

    -- Fallback: last bucket (should not happen since last bucket is math.huge)
    return count / buckets[#buckets].divisor
end

---Extract text from an item (ReferItem table or raw string).
---@param item ReferItem|string
---@return string|nil
local function item_text(item)
    if type(item) == "string" then
        return item
    end
    if type(item) == "table" then
        return item.text
    end
    return nil
end

---Resolve the frecency key for an item using the given strategy.
---Built-in strategies: "text", "filepath", "filepath_with_lnum".
---Custom strategies: a function receiving the item and returning a string key.
---Falls back to "text" strategy when the strategy/key resolution produces nil.
---@param item ReferItem|nil The item to resolve a key for
---@param strategy string|function|nil Strategy name or custom function
---@return string|nil resolved_key
function M.resolve_key(item, strategy)
    if item == nil then
        return nil
    end

    -- Resolve text for fallback
    local text = item_text(item)
    if text == nil then
        return nil
    end

    if strategy == nil then
        return text
    end

    -- Custom function strategy
    if type(strategy) == "function" then
        local key = strategy(item)
        if key ~= nil then
            return key
        end
        return text -- fallback to text
    end

    -- String-based strategies
    if strategy == "text" then
        return text
    end

    if strategy == "filepath" then
        if type(item) == "table" and item.data and item.data.filename then
            return vim.fn.fnamemodify(item.data.filename, ":p")
        end
        return text -- fallback
    end

    if strategy == "filepath_with_lnum" then
        if type(item) == "table" and item.data and item.data.filename and item.data.lnum then
            return vim.fn.fnamemodify(item.data.filename, ":p") .. ":" .. tostring(item.data.lnum)
        end
        return text -- fallback
    end

    -- Unknown strategy → fallback to text
    return text
end

---Reorder items within fuzzy score neighborhoods by frecency score.
---Items are already sorted by fuzzy score from the sorter.
---Consecutive items form neighborhoods of size `neighborhood_size`.
---Within each neighborhood, items with higher frecency scores come first.
---Items without a frecency score appear after scored items, preserving original order.
---When opts.scores is nil, items are returned unchanged.
---@param items ReferItem[]|string[] Items in fuzzy-score order
---@param opts table { scores = table<string, number>|nil, frecency_scores = table<string, number>|nil, neighborhood_size = number|nil, resolve_fn = fun(item: ReferItem|string): string|nil }
---@return table reordered_items
function M.reorder(items, opts)
    if #items == 0 then
        return {}
    end

    local scores = opts and opts.scores
    if not scores or next(scores) == nil then
        -- No fuzzy scores → return unchanged (non-lua sorter path)
        return items
    end

    local frecency_scores = opts.frecency_scores or {}
    local neighborhood_size = (opts.neighborhood_size and opts.neighborhood_size > 0) and opts.neighborhood_size or 10
    ---@type fun(item: ReferItem|string): string|nil
    local resolve_fn = opts.resolve_fn or item_text

    -- Build array with text accessor and fuzzy score
    local entries = {}
    for i, item in ipairs(items) do
        local text = item_text(item)
        local resolved_key = resolve_fn(item)
        local fuzzy_score = text and scores[text]
        local frecency = (resolved_key and frecency_scores[resolved_key]) or nil
        table.insert(entries, {
            item = item,
            key = resolved_key,
            original_index = i,
            fuzzy_score = fuzzy_score,
            frecency = frecency,
        })
    end

    -- Separate scored and unscored items
    local scored = {}
    local unscored = {}
    for _, entry in ipairs(entries) do
        if entry.fuzzy_score ~= nil then
            table.insert(scored, entry)
        else
            table.insert(unscored, entry)
        end
    end

    -- Group scored items into neighborhoods: consecutive items with the same
    -- fuzzy score form a neighborhood, capped at neighborhood_size.
    -- Items with different scores are always in different neighborhoods.
    local neighborhoods = {}
    local current_group = {}
    local current_score = nil
    local current_group_size = 0

    local function flush_group()
        if #current_group > 0 then
            -- Sort group: frecency desc, then original order for ties/unscored
            table.sort(current_group, function(a, b)
                local fa = a.frecency
                local fb = b.frecency
                if fa ~= nil and fb == nil then
                    return true
                end
                if fa == nil and fb ~= nil then
                    return false
                end
                if fa ~= nil and fb ~= nil and fa ~= fb then
                    return fa > fb
                end
                return a.original_index < b.original_index
            end)
            table.insert(neighborhoods, current_group)
            current_group = {}
            current_group_size = 0
        end
    end

    for _, entry in ipairs(scored) do
        local score_changed = (current_score ~= nil and entry.fuzzy_score ~= current_score)
        local group_full = (current_group_size >= neighborhood_size)

        if score_changed or group_full then
            flush_group()
            current_score = entry.fuzzy_score
        elseif current_score == nil then
            current_score = entry.fuzzy_score
        end

        table.insert(current_group, entry)
        current_group_size = current_group_size + 1
    end
    flush_group()

    -- Build result from neighborhoods, then append unscored
    local reordered = {}
    for _, group in ipairs(neighborhoods) do
        for _, entry in ipairs(group) do
            table.insert(reordered, entry.item)
        end
    end
    for _, entry in ipairs(unscored) do
        table.insert(reordered, entry.item)
    end

    return reordered
end

---Sort items entirely by frecency score (for empty-query path).
---Items with frecency scores come first (descending), then unscored items in original order.
---@param items ReferItem[]|string[] Items to sort
---@param frecency_scores table<string, number> Map of item_key → frecency_score
---@param resolve_fn? fun(item: ReferItem|string): string|nil Key resolver (defaults to item_text)
---@return table sorted_items
function M.sort_by_frecency(items, frecency_scores, resolve_fn)
    if #items == 0 then
        return {}
    end

    frecency_scores = frecency_scores or {}
    resolve_fn = resolve_fn or item_text

    local entries = {}
    for i, item in ipairs(items) do
        local key = resolve_fn(item)
        local frecency = (key and frecency_scores[key]) or nil
        table.insert(entries, {
            item = item,
            original_index = i,
            frecency = frecency,
        })
    end

    -- Stable sort: frecency desc, then original order for ties/unscored
    table.sort(entries, function(a, b)
        local fa = a.frecency
        local fb = b.frecency
        -- Items with frecency before items without
        if fa ~= nil and fb == nil then
            return true
        end
        if fa == nil and fb ~= nil then
            return false
        end
        -- Both have frecency: higher first
        if fa ~= nil and fb ~= nil then
            if fa ~= fb then
                return fa > fb
            end
        end
        -- Equal or both nil: preserve original order
        return a.original_index < b.original_index
    end)

    local result = {}
    for _, entry in ipairs(entries) do
        table.insert(result, entry.item)
    end
    return result
end

return M
