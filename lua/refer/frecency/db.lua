local score = require "refer.frecency.score"

local M = {}

local db_path = nil
local clock_fn = nil
local noop_mode = false
local warned_noop = false
local warned_cleanup = false
local noop_reason = nil
local did_operate = false
local max_entries_per_provider = 10000
local cleanup_max_age_seconds = 180 * 86400
local cleanup_buckets = nil

local function default_store()
    return {
        version = 1,
        providers = {},
    }
end

local function resolved_path()
    return db_path or (vim.fn.stdpath "data" .. "/refer/frecency.json")
end

local function warn_once(message)
    if warned_noop then
        return
    end
    warned_noop = true
    vim.notify("[refer.frecency] " .. message .. " — switching to no-op mode", vim.log.levels.WARN)
end

local function enter_noop(message)
    noop_mode = true
    noop_reason = message
    warn_once(message)
end

local function warn_cleanup_once(message)
    if warned_cleanup then
        return
    end
    warned_cleanup = true
    vim.notify("[refer.frecency] " .. message, vim.log.levels.WARN)
end

local function now_sec()
    if clock_fn then
        return clock_fn()
    end
    return vim.loop.hrtime() / 1e9
end

local function normalize_store(store)
    if type(store) ~= "table" then
        return nil
    end
    if store.version == nil then
        store.version = 1
    end
    if store.version ~= 1 then
        return nil
    end
    if store.providers == nil then
        store.providers = {}
    end
    if type(store.providers) ~= "table" then
        return nil
    end
    return store
end

local function read_file(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
        return nil, lines
    end
    return table.concat(lines, "\n"), nil
end

local function load_store()
    if noop_mode then
        return nil
    end

    local path = resolved_path()
    if vim.fn.filereadable(path) == 0 then
        local ftype = vim.fn.getftype(path)
        if ftype ~= "" and ftype ~= "dir" then
            enter_noop("Could not read JSON store at " .. path .. ": unreadable")
            return nil
        end
        return default_store()
    end

    local content, read_err = read_file(path)
    if not content then
        enter_noop("Could not read JSON store at " .. path .. ": " .. tostring(read_err))
        return nil
    end

    local ok, decoded = pcall(vim.json.decode, content)
    if not ok then
        enter_noop("Could not decode JSON store at " .. path .. ": " .. tostring(decoded))
        return nil
    end

    local store = normalize_store(decoded)
    if not store then
        enter_noop("Invalid JSON store shape at " .. path)
        return nil
    end

    return store
end

local function write_store(store, opts)
    if noop_mode then
        return false
    end

    opts = opts or {}
    local function fail(message)
        if opts.no_noop then
            warn_cleanup_once(message)
        else
            enter_noop(message)
        end
        return false
    end

    local path = resolved_path()
    local dir = vim.fn.fnamemodify(path, ":h")
    local ok_mkdir, mkdir_err = pcall(vim.fn.mkdir, dir, "p")
    if not ok_mkdir then
        return fail("Could not create store directory " .. dir .. ": " .. tostring(mkdir_err))
    end

    local ok_encode, encoded = pcall(vim.json.encode, store)
    if not ok_encode then
        return fail("Could not encode JSON store: " .. tostring(encoded))
    end

    local tmp_path = path .. ".tmp." .. tostring(vim.loop.hrtime())
    local ok_write, write_err = pcall(vim.fn.writefile, { encoded }, tmp_path)
    if not ok_write or write_err ~= 0 then
        pcall(vim.fn.delete, tmp_path)
        return fail("Could not write temporary JSON store " .. tmp_path .. ": " .. tostring(write_err))
    end

    local ok_rename, rename_result = pcall(vim.fn.rename, tmp_path, path)
    if not ok_rename or rename_result ~= 0 then
        pcall(vim.fn.delete, tmp_path)
        return fail("Could not replace JSON store at " .. path .. ": " .. tostring(rename_result))
    end

    return true
end

function M.configure(opts)
    opts = opts or {}
    if opts.db_path then
        db_path = opts.db_path
    end
    if opts.clock_fn then
        clock_fn = opts.clock_fn
    end
    if opts.max_entries_per_provider ~= nil then
        max_entries_per_provider = opts.max_entries_per_provider
    end
    if opts.cleanup_max_age_days ~= nil then
        cleanup_max_age_seconds = opts.cleanup_max_age_days * 86400
    end
    if opts.buckets ~= nil then
        cleanup_buckets = (opts.buckets == false) and nil or opts.buckets
    end
end

function M.record(provider, item_key, opts)
    if not provider or provider == "" or not item_key or item_key == "" then
        return
    end

    -- [TEST-ONLY] opts.clock_fn mutates the module-level clock_fn.
    -- This is a test injection mechanism; production code should pass
    -- clock_fn via configure() only. See M.configure().
    if opts and opts.clock_fn then
        clock_fn = opts.clock_fn
    end

    did_operate = true

    local store = load_store()
    if not store then
        return
    end

    local providers = store.providers
    providers[provider] = providers[provider] or {}
    local provider_store = providers[provider]
    local record = provider_store[item_key]
    if record then
        record.selected_count = (tonumber(record.selected_count) or 0) + 1
        record.last_selected_at = now_sec()
    else
        provider_store[item_key] = {
            selected_count = 1,
            last_selected_at = now_sec(),
        }
    end

    write_store(store)
end

function M.read_scores(provider, item_keys, opts)
    if not provider or provider == "" or not item_keys or #item_keys == 0 then
        return {}
    end

    -- [TEST-ONLY] opts.clock_fn mutates the module-level clock_fn.
    -- This is a test injection mechanism; production code should pass
    -- clock_fn via configure() only. See M.configure().
    if opts and opts.clock_fn then
        clock_fn = opts.clock_fn
    end

    did_operate = true

    local store = load_store()
    if not store then
        return {}
    end

    local provider_store = store.providers[provider]
    if type(provider_store) ~= "table" then
        return {}
    end

    local now = now_sec()
    local buckets = (opts and opts.buckets) or nil
    local result = {}
    for _, key in ipairs(item_keys) do
        local record = provider_store[key]
        if type(record) == "table" then
            local count = tonumber(record.selected_count) or 0
            local last_selected = tonumber(record.last_selected_at)
            local age = last_selected and (now - last_selected) or math.huge
            result[key] = score.compute(count, age, buckets)
        end
    end

    return result
end

---@return boolean changed Whether cleanup rewrote the store
function M.cleanup()
    if noop_mode or not did_operate then
        return false
    end

    local ok, changed = pcall(function()
        local store = load_store()
        if not store then
            return false
        end

        local now = now_sec()
        local store_changed = false
        for _, provider_store in pairs(store.providers) do
            if type(provider_store) == "table" then
                for item_key, record in pairs(provider_store) do
                    local last_selected = type(record) == "table" and tonumber(record.last_selected_at) or nil
                    local age = last_selected and (now - last_selected) or math.huge
                    if age > cleanup_max_age_seconds then
                        provider_store[item_key] = nil
                        store_changed = true
                    end
                end

                local entries = {}
                for item_key, record in pairs(provider_store) do
                    if type(record) == "table" then
                        local count = tonumber(record.selected_count) or 0
                        local last_selected = tonumber(record.last_selected_at)
                        local age = last_selected and (now - last_selected) or math.huge
                        table.insert(entries, {
                            item_key = item_key,
                            selected_count = count,
                            last_selected_at = last_selected or -math.huge,
                            frecency = score.compute(count, age, cleanup_buckets),
                        })
                    end
                end

                if #entries > max_entries_per_provider then
                    table.sort(entries, function(a, b)
                        if a.frecency ~= b.frecency then
                            return a.frecency < b.frecency
                        end
                        if a.last_selected_at ~= b.last_selected_at then
                            return a.last_selected_at < b.last_selected_at
                        end
                        if a.selected_count ~= b.selected_count then
                            return a.selected_count < b.selected_count
                        end
                        return a.item_key < b.item_key
                    end)

                    for i = 1, #entries - max_entries_per_provider do
                        provider_store[entries[i].item_key] = nil
                        store_changed = true
                    end
                end
            end
        end

        if store_changed then
            return write_store(store, { no_noop = true })
        end
        return false
    end)

    if not ok then
        warn_cleanup_once("Cleanup failed: " .. tostring(changed))
        return false
    end
    return changed or false
end

function M.is_available()
    return not noop_mode
end

---Return the resolved JSON store path (even when disabled).
---@return string
function M.get_path()
    return resolved_path()
end

---Return the reason for entering no-op mode, or nil if not in no-op.
---@return string|nil
function M.get_noop_reason()
    return noop_reason
end

function M._reset()
    db_path = nil
    clock_fn = nil
    noop_mode = false
    warned_noop = false
    warned_cleanup = false
    noop_reason = nil
    did_operate = false
    max_entries_per_provider = 10000
    cleanup_max_age_seconds = 180 * 86400
    cleanup_buckets = nil
end

return M
