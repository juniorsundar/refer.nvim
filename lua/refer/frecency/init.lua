local db = require "refer.frecency.db"
local score_mod = require "refer.frecency.score"

local M = {}

-- Module configuration (buckets and neighborhood_size are used by this module,
-- db_path and clock_fn are passed through to db)
local config = {
    buckets = nil,
    neighborhood_size = 10,
}

---Configure the frecency module.
---Accepts: db_path, buckets, neighborhood_size, clock_fn.
---db_path and clock_fn are passed through to the db module.
---buckets and neighborhood_size are stored for use in score/reorder.
---@param opts table
function M.configure(opts)
    opts = opts or {}

    -- Store score-related config locally
    if opts.buckets ~= nil then
        config.buckets = (opts.buckets == false) and nil or opts.buckets
    end
    if opts.neighborhood_size ~= nil then
        config.neighborhood_size = opts.neighborhood_size
    end

    -- Pass through to db
    db.configure {
        db_path = opts.db_path,
        clock_fn = opts.clock_fn,
    }
end

---Record a selection event.
---No-op when provider or item_key is nil/empty.
---@param provider string|nil
---@param item_key string|nil
---@param opts? table { clock_fn = function|nil }
function M.record(provider, item_key, opts)
    if not provider or provider == "" or not item_key or item_key == "" then
        return
    end
    db.record(provider, item_key, opts)
end

---Read frecency scores for multiple item keys within a provider.
---Returns a map: { [item_key] = frecency_score_number }.
---Keys without records are absent from the map.
---@param provider string
---@param item_keys string[]
---@param opts? table { clock_fn = function|nil }
---@return table<string, number>
function M.score(provider, item_keys, opts)
    if not provider or provider == "" or not item_keys or #item_keys == 0 then
        return {}
    end
    opts = opts or {}
    -- Pass configured buckets through to db for score computation
    if config.buckets then
        opts.buckets = config.buckets
    end
    return db.read_scores(provider, item_keys, opts)
end

---Reorder items within fuzzy score neighborhoods by frecency.
---When opts.scores is nil, items are returned unchanged (non-lua sorter path).
---Otherwise, items are grouped into neighborhoods of similar fuzzy score
---and reordered within each neighborhood by frecency score.
---@param provider string
---@param items ReferItem[]|string[]
---@param opts table { scores = table<string, number>|nil, frecency_scores = table<string, number>|nil, neighborhood_size = number|nil }
---@return table reordered_items
function M.reorder(provider, items, opts)
    opts = opts or {}

    -- Nil/empty provider: no-op
    if not provider or provider == "" then
        return items
    end

    -- Use provided frecency_scores, or compute from provider/item keys
    local frecency_scores = opts.frecency_scores
    if not frecency_scores and provider and provider ~= "" then
        local item_keys = {}
        for _, item in ipairs(items) do
            local key = score_mod.resolve_key(item, "text")
            if key then
                table.insert(item_keys, key)
            end
        end
        if #item_keys > 0 then
            frecency_scores = db.read_scores(provider, item_keys, {
                clock_fn = opts.clock_fn,
                buckets = config.buckets,
            })
        end
    end
    frecency_scores = frecency_scores or {}

    -- Empty-query: no fuzzy scores → sort entirely by frecency
    if not opts.scores or next(opts.scores) == nil then
        return score_mod.sort_by_frecency(items, frecency_scores)
    end

    -- With fuzzy scores: neighborhood-based reordering
    local reorder_opts = {
        scores = opts.scores,
        frecency_scores = frecency_scores,
        neighborhood_size = opts.neighborhood_size or config.neighborhood_size,
    }

    return score_mod.reorder(items, reorder_opts)
end

---Resolve the frecency key for an item using the given strategy.
---@param item ReferItem|nil
---@param strategy string|function|nil
---@return string|nil resolved_key
function M.resolve_key(item, strategy)
    return score_mod.resolve_key(item, strategy)
end

---Check whether the frecency backend is available and functional.
---@return boolean
function M.is_available()
    return db.is_available()
end

return M
