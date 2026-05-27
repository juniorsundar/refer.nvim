local db = require "refer.frecency.db"
local score_mod = require "refer.frecency.score"

local M = {}

-- Module configuration (buckets and neighborhood_size are used by this module,
-- db_path and clock_fn are passed through to db)
local config = {
    enabled = true,
    buckets = nil,
    neighborhood_size = 10,
}

---Configure the frecency module.
---Accepts: enabled, db_path, buckets, neighborhood_size, clock_fn.
---db_path and clock_fn are passed through to the db module.
---buckets, neighborhood_size, and enabled are stored for use in score/reorder.
---@param opts table
function M.configure(opts)
    opts = opts or {}

    -- Store score-related config locally
    if opts.enabled ~= nil then
        config.enabled = opts.enabled
    end
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
---No-op when provider or item_key is nil/empty, or when globally disabled.
---@param provider string|nil
---@param item_key string|nil
---@param opts? table { clock_fn = function|nil }
function M.record(provider, item_key, opts)
    if not config.enabled or config.enabled == false then
        return
    end
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
    if not config.enabled or config.enabled == false then
        return {}
    end
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
---@param opts table { scores = table<string, number>|nil, frecency_scores = table<string, number>|nil, neighborhood_size = number|nil, key_strategy = string|fun(item: ReferItem): string, clock_fn = function|nil }
---@return table reordered_items
function M.reorder(provider, items, opts)
    opts = opts or {}

    -- Nil/empty items: no-op
    if not items or type(items) ~= "table" then
        return {}
    end

    -- Globally disabled: return items unchanged
    if not config.enabled or config.enabled == false then
        return items
    end

    if not db.is_available() then
        return items
    end

    -- Nil/empty provider: no-op
    if not provider or provider == "" then
        return items
    end

    -- Build a key resolver based on the strategy
    local key_strategy = opts.key_strategy or "text"
    local resolve_fn
    if type(key_strategy) == "function" then
        resolve_fn = key_strategy
    else
        resolve_fn = function(item)
            return score_mod.resolve_key(item, key_strategy)
        end
    end

    -- Use provided frecency_scores, or compute from provider/item keys
    local frecency_scores = opts.frecency_scores
    if not frecency_scores and provider and provider ~= "" then
        local item_keys = {}
        for _, item in ipairs(items) do
            local key = resolve_fn(item)
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
        return score_mod.sort_by_frecency(items, frecency_scores, resolve_fn)
    end

    -- With fuzzy scores: neighborhood-based reordering
    local reorder_opts = {
        scores = opts.scores,
        frecency_scores = frecency_scores,
        neighborhood_size = opts.neighborhood_size or config.neighborhood_size,
        resolve_fn = resolve_fn,
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

---Check whether frecency is globally enabled.
---@return boolean
function M.is_enabled()
    return config.enabled ~= false
end

---Return the current frecency status as a structured table.
---Shape: { enabled, store_available, active, no_op, reason, db_path }
---@return table
function M.status()
    local enabled = config.enabled ~= false
    local no_op = enabled and not db.is_available()
    local store_available = enabled and not no_op
    local active = enabled and not no_op

    local reason = nil
    if not enabled then
        reason = "disabled by config"
    elseif no_op then
        reason = db.get_noop_reason()
    end

    return {
        enabled = enabled,
        store_available = store_available,
        active = active,
        no_op = no_op,
        reason = reason,
        db_path = db.get_path(),
    }
end

---Get the configured neighborhood size.
---@return number neighborhood_size
function M.get_neighborhood_size()
    return config.neighborhood_size or 10
end

return M
