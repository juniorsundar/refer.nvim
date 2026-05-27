local db = require "refer.frecency.db"

local function temp_path(suffix)
    return vim.fn.tempname() .. (suffix or "_frecency.json")
end

local function cleanup_path(path)
    if path and path ~= "" then
        vim.fn.delete(path, "rf")
        vim.fn.delete(vim.fn.fnamemodify(path, ":h"), "rf")
    end
end

local function read_json(path)
    local content = table.concat(vim.fn.readfile(path), "\n")
    return vim.json.decode(content)
end

local current_time = 0

local function configure_json(path)
    db.configure {
        db_path = path,
        clock_fn = function()
            return current_time
        end,
    }
end

describe("refer.frecency.db", function()
    local path

    before_each(function()
        path = temp_path()
        current_time = 0
        db._reset()
        configure_json(path)
    end)

    after_each(function()
        db._reset()
        cleanup_path(path)
    end)

    describe("initialization", function()
        it("creates the JSON store and parent directory on first write", function()
            local nested = temp_path "/nested/frecency.json"
            path = nested
            db._reset()
            configure_json(path)

            assert.is_false(vim.fn.filereadable(path) == 1)
            current_time = 1000
            db.record("test_provider", "item1")

            assert.is_true(vim.fn.filereadable(path) == 1)
            local store = read_json(path)
            assert.are.equal(1, store.version)
            assert.is_table(store.providers.test_provider.item1)
        end)

        it("accepts configurable db_path", function()
            current_time = 1000
            db.record("p", "k")
            assert.is_true(vim.fn.filereadable(path) == 1)
        end)

        it("starts from an empty store when the file is missing", function()
            current_time = 1000
            local scores = db.read_scores("p", { "missing" })
            assert.are.same({}, scores)
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)
    end)

    describe("record()", function()
        it("uses the configured clock for timestamps", function()
            local now = 1000000
            db.configure {
                db_path = path,
                clock_fn = function()
                    return now
                end,
            }

            db.record("buffers", "item_a")
            now = now + 3600

            local scores = db.read_scores("buffers", { "item_a" })
            assert.are.equal(0.5, scores.item_a)
        end)

        it("inserts a new record with count=1 and a timestamp", function()
            local fixed_time = 1000000
            current_time = fixed_time
            db.record("buffers", "item_a")

            local store = read_json(path)
            local record = store.providers.buffers.item_a
            assert.are.equal(1, record.selected_count)
            assert.are.equal(fixed_time, record.last_selected_at)

            current_time = fixed_time + 3600
            local scores = db.read_scores("buffers", { "item_a" })
            assert.are.equal(0.5, scores.item_a)
        end)

        it("increments count and updates timestamp on repeat selections", function()
            local t0 = 1000000
            current_time = t0
            db.record("buffers", "item_a")
            current_time = t0 + 100
            db.record("buffers", "item_a")

            local store = read_json(path)
            local record = store.providers.buffers.item_a
            assert.are.equal(2, record.selected_count)
            assert.are.equal(t0 + 100, record.last_selected_at)

            current_time = t0 + 100
            local scores = db.read_scores("buffers", { "item_a" })
            assert.are.equal(2, scores.item_a)
        end)

        it("count accumulates across many selections", function()
            local t = 1000000
            for _ = 1, 10 do
                current_time = t
                db.record("test", "popular")
                t = t + 100
            end

            current_time = t
            local scores = db.read_scores("test", { "popular" })
            assert.are.equal(10, scores.popular)
        end)

        it("is a no-op when provider is nil", function()
            current_time = 1000
            db.record(nil, "item")
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when provider is empty string", function()
            current_time = 1000
            db.record("", "item")
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when item_key is nil", function()
            current_time = 1000
            db.record("p", nil)
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when item_key is empty string", function()
            current_time = 1000
            db.record("p", "")
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)
    end)

    describe("read_scores()", function()
        it("returns scores for multiple item keys", function()
            local now = 1000000
            current_time = now
            db.record("files", "file_a")
            current_time = now - 86400
            db.record("files", "file_b")
            current_time = now - 604800
            db.record("files", "file_c")

            current_time = now
            local scores = db.read_scores("files", { "file_a", "file_b", "file_c" })

            assert.are.equal(1, scores.file_a)
            assert.are.equal(0.25, scores.file_b)
            assert.are.equal(0.125, scores.file_c)
        end)

        it("keys without records are absent from the result map", function()
            local now = 1000000
            current_time = now
            db.record("p", "exists")

            current_time = now
            local scores = db.read_scores("p", { "exists", "missing" })
            assert.is_not_nil(scores.exists)
            assert.is_nil(scores.missing)
        end)

        it("returns empty map for empty item_keys", function()
            current_time = 0
            local scores = db.read_scores("p", {})
            assert.are.same({}, scores)
        end)

        it("returns empty map when provider is nil", function()
            current_time = 0
            local scores = db.read_scores(nil, { "k" })
            assert.are.same({}, scores)
        end)

        it("providers are isolated", function()
            local t = 1000000
            current_time = t
            db.record("buffers", "item")
            current_time = t - 3600
            db.record("files", "item")

            current_time = t
            local buf_scores = db.read_scores("buffers", { "item" })
            current_time = t
            local file_scores = db.read_scores("files", { "item" })

            assert.are.equal(1, buf_scores.item)
            assert.are.equal(0.5, file_scores.item)
        end)

        it("treats missing timestamps as the lowest recency bucket", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({
                vim.json.encode {
                    version = 1,
                    providers = {
                        p = {
                            stale = { selected_count = 8 },
                        },
                    },
                },
            }, path)

            current_time = 1000
            local scores = db.read_scores("p", { "stale" })
            assert.are.equal(1, scores.stale) -- 8 / divisor 8
        end)
    end)

    describe("JSON failure handling", function()
        it("enters no-op mode on corrupt JSON and leaves file untouched", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, path)

            current_time = 1000
            local scores = db.read_scores("p", { "k" })
            assert.are.same({}, scores)
            assert.is_false(db.is_available())
            assert.are.same({ "{not json" }, vim.fn.readfile(path))

            current_time = 1000
            db.record("p", "k")
            assert.are.same({ "{not json" }, vim.fn.readfile(path))
        end)

        it("enters no-op mode on unreadable JSON store and leaves file untouched", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            local original_content = vim.json.encode {
                version = 1,
                providers = {
                    p = {
                        k = { selected_count = 1, last_selected_at = 1000 },
                    },
                },
            }
            vim.fn.writefile({ original_content }, path)
            vim.fn.setfperm(path, "---------")

            local original_notify = vim.notify
            local notifications = {}
            vim.notify = function(message, level)
                table.insert(notifications, { message = message, level = level })
            end

            current_time = 2000
            local scores = db.read_scores("p", { "k" })
            db.record("p", "other")

            vim.notify = original_notify
            vim.fn.setfperm(path, "rw-r--r--")

            assert.are.same({}, scores)
            assert.is_false(db.is_available())
            assert.are.same({ original_content }, vim.fn.readfile(path))
            assert.are.same(1, #notifications)
            assert.are.same(vim.log.levels.WARN, notifications[1].level)
            assert.is_true(notifications[1].message:find("Could not read JSON store", 1, true) ~= nil)
        end)

        it("enters no-op mode when atomic rename fails", function()
            local dir_path = temp_path "_as_dir"
            path = dir_path
            vim.fn.mkdir(path, "p")
            db._reset()
            configure_json(path)

            current_time = 1000
            db.record("p", "k")
            assert.is_false(db.is_available())
            assert.is_true(vim.fn.isdirectory(path) == 1)
        end)

        it("subsequent record() after noop mode does not retry or touch store", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, path)

            current_time = 1000
            local scores = db.read_scores("p", { "k" })
            assert.are.same({}, scores)
            assert.is_false(db.is_available())
            local original_content = vim.fn.readfile(path)

            -- Subsequent operations should be no-ops
            db.record("p", "k2")
            current_time = 1000
            local scores2 = db.read_scores("p", { "k2" })
            assert.are.same({}, scores2)

            -- File should be untouched
            assert.are.same(original_content, vim.fn.readfile(path))
        end)

        it("subsequent record() after write-failure noop does not retry", function()
            local dir_path = temp_path "_as_dir"
            path = dir_path
            vim.fn.mkdir(path, "p")
            db._reset()
            configure_json(path)

            current_time = 1000
            db.record("p", "k")
            assert.is_false(db.is_available())

            -- Remove the blocking directory so write would succeed IF we retried
            vim.fn.delete(path, "rf")

            -- Subsequent operation should still be a no-op
            current_time = 2000
            db.record("p", "k2")
            -- No file should have been created
            assert.is_true(vim.fn.filereadable(path) == 0)
        end)
    end)

    describe("in-memory cache", function()
        it("serves recorded data from cache after the on-disk file is deleted", function()
            current_time = 1000
            db.record("buffers", "cached_item")

            -- Verify the file exists on disk
            assert.is_true(vim.fn.filereadable(path) == 1)

            -- Delete the on-disk JSON file
            vim.fn.delete(path)
            assert.is_false(vim.fn.filereadable(path) == 1)

            -- read_scores should still return the recorded data from cache
            current_time = 1000
            local scores = db.read_scores("buffers", { "cached_item" })
            assert.are.equal(1, scores.cached_item)
        end)

        it("invalidates cache on persistence failure and enters no-op mode", function()
            -- First record populates the cache
            current_time = 1000
            db.record("test", "item")
            assert.is_true(db.is_available())

            -- Make the file path a directory so the next write fails
            vim.fn.delete(path)
            vim.fn.mkdir(path, "p")

            -- This write will fail because path is now a directory
            current_time = 2000
            db.record("test", "item2")

            -- Cache should be invalidated and no-op mode entered
            assert.is_false(db.is_available())
            current_time = 2000
            local scores = db.read_scores("test", { "item" })
            assert.are.same({}, scores)

            -- Subsequent record should be a no-op
            current_time = 3000
            db.record("test", "item3")
            -- File at path is still a directory (not a JSON file)
            assert.is_true(vim.fn.isdirectory(path) == 1)
        end)

        it("clears cache on _reset so re-configure reads from disk, not stale cache", function()
            current_time = 1000
            db.record("p", "stale_item")

            -- Verify this is on disk
            local store = read_json(path)
            assert.are.equal(1, store.providers.p.stale_item.selected_count)

            -- Reset clears cached_store
            db._reset()

            -- Write a different item to the same file while cache is cleared
            vim.fn.writefile({
                vim.json.encode {
                    version = 1,
                    providers = {
                        p = {
                            fresh_item = {
                                selected_count = 5,
                                last_selected_at = 2000,
                            },
                        },
                    },
                },
            }, path)

            -- Re-configure to the same path and read
            configure_json(path)
            current_time = 2000
            local scores = db.read_scores("p", { "stale_item", "fresh_item" })

            -- stale_item was in cache before reset; after reset, it should NOT be found
            assert.is_nil(scores.stale_item)
            -- fresh_item exists on disk and should be found via fresh read
            assert.is_not_nil(scores.fresh_item)
            assert.are.equal(5, scores.fresh_item)
        end)

        it("invalidates cache when db_path changes, reading from new path and back", function()
            -- Record data at path A
            current_time = 1000
            db.record("test", "item_on_a")

            -- Configure to path B
            local path_b = temp_path "_frecency_b.json"
            db.configure {
                db_path = path_b,
                clock_fn = function()
                    return current_time
                end,
            }

            -- read_scores from path B should return empty (no data there, cache invalidated)
            current_time = 1000
            local scores_b = db.read_scores("test", { "item_on_a" })
            assert.are.same({}, scores_b)
            assert.is_true(db.is_available())

            -- Record something on path B
            current_time = 2000
            db.record("test", "item_on_b")

            -- Configure back to path A
            db.configure {
                db_path = path,
                clock_fn = function()
                    return current_time
                end,
            }

            -- read_scores from path A should return original data (re-read from disk, not stale cache)
            current_time = 1000
            local scores_a = db.read_scores("test", { "item_on_a", "item_on_b" })
            assert.is_not_nil(scores_a.item_on_a)
            assert.are.equal(1, scores_a.item_on_a)
            assert.is_nil(scores_a.item_on_b) -- item_on_b was recorded on path B, not here

            cleanup_path(path_b)
        end)

        it("invalidates cache when db_path is reconfigured to the same path", function()
            current_time = 1000
            db.record("test", "cached_item")
            assert.are.equal(1, db.read_scores("test", { "cached_item" }).cached_item)

            vim.fn.writefile({
                vim.json.encode {
                    version = 1,
                    providers = {
                        test = {
                            disk_item = {
                                selected_count = 4,
                                last_selected_at = 1000,
                            },
                        },
                    },
                },
            }, path)

            db.configure {
                db_path = path,
                clock_fn = function()
                    return current_time
                end,
            }

            local scores = db.read_scores("test", { "cached_item", "disk_item" })
            assert.is_nil(scores.cached_item)
            assert.are.equal(4, scores.disk_item)
        end)

        it("uses mutable-closure clock consistently with cache for record and read", function()
            local t = 1000000
            db.configure {
                db_path = path,
                clock_fn = function()
                    return t
                end,
            }

            -- Record at time T
            t = 1000000
            db.record("test", "timed_item")

            -- Advance clock to T+3600 and read scores
            t = t + 3600
            local scores = db.read_scores("test", { "timed_item" })

            -- Score should reflect the 3600-second age (bucket divisor 2 → score = 1 / 2 = 0.5)
            assert.are.equal(0.5, scores.timed_item)

            -- Advance further to T+86400 and read again (should use cached store + current clock)
            t = t + 82800
            local scores2 = db.read_scores("test", { "timed_item" })
            assert.are.equal(0.25, scores2.timed_item)
        end)

        it("cleanup writes through cached store to disk with in-session writes", function()
            -- Record a fresh entry and an old entry during this session
            current_time = 1000000
            db.record("buffers", "keep_me")
            current_time = 1
            db.record("buffers", "evict_me")

            -- Verify both are on disk
            local store_before = read_json(path)
            assert.is_table(store_before.providers.buffers.keep_me)
            assert.is_table(store_before.providers.buffers.evict_me)

            -- Configure cleanup to evict entries older than 1 day without invalidating the cache
            db.configure {
                clock_fn = function()
                    return current_time
                end,
                cleanup_max_age_days = 1,
            }

            -- Delete the on-disk file to prove cleanup writes from cache, not disk
            vim.fn.delete(path)
            assert.is_false(vim.fn.filereadable(path) == 1)

            -- Run cleanup — evict_me is ~11.5 days old, should be evicted, triggering write_store from cache
            current_time = 1000000
            db.cleanup()

            -- File should be recreated with the cached data (only keep_me remains)
            assert.is_true(vim.fn.filereadable(path) == 1)
            local store_after = read_json(path)
            assert.is_table(store_after.providers.buffers.keep_me)
            assert.are.equal(1, store_after.providers.buffers.keep_me.selected_count)
            assert.is_nil(store_after.providers.buffers.evict_me)
        end)

        it("returns and caches default_store when JSON file does not exist", function()
            -- Path has never been written to — file doesn't exist
            assert.is_false(vim.fn.filereadable(path) == 1)

            -- read_scores should return empty (load_store returns default_store)
            current_time = 1000
            local scores = db.read_scores("p", { "k" })
            assert.are.same({}, scores)
            assert.is_true(db.is_available())

            -- No file should have been created by a read
            assert.is_false(vim.fn.filereadable(path) == 1)

            -- First record() call should create the file
            current_time = 2000
            db.record("p", "first_item")
            assert.is_true(vim.fn.filereadable(path) == 1)

            local store = read_json(path)
            assert.are.equal(1, store.providers.p.first_item.selected_count)
        end)

        it("normalizes and caches minimal JSON file", function()
            -- Write an empty JSON object to the file
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({ "{}" }, path)

            -- read_scores should work (normalize_store sets version=1, providers={})
            current_time = 1000
            local scores = db.read_scores("p", { "k" })
            assert.are.same({}, scores)
            assert.is_true(db.is_available())

            -- Record should work and write the normalized store
            current_time = 2000
            db.record("p", "item")

            local store = read_json(path)
            assert.are.equal(1, store.version)
            assert.is_table(store.providers)
            assert.are.equal(1, store.providers.p.item.selected_count)
        end)

        it("sets cached_store to nil on persistence failure, returning no stale data", function()
            -- First record populates the cache with data
            current_time = 1000
            db.record("test", "pre_failure_item")
            assert.is_true(db.is_available())

            -- Verify the cache has the data
            current_time = 1000
            local scores_before = db.read_scores("test", { "pre_failure_item" })
            assert.are.equal(1, scores_before.pre_failure_item)

            -- Switch to a new path with a corrupt file so cache is invalidated and read fails
            local corrupt_path = temp_path "_corrupt_frecency.json"
            vim.fn.mkdir(vim.fn.fnamemodify(corrupt_path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, corrupt_path)

            -- Configure the corrupt path — cache is cleared and load_store will hit corrupt file
            db.configure {
                db_path = corrupt_path,
                clock_fn = function()
                    return current_time
                end,
            }

            -- read_scores triggers load_store which fails → enters no-op, clears cache
            current_time = 2000
            local scores_after = db.read_scores("test", { "pre_failure_item" })
            assert.are.same({}, scores_after)
            assert.is_false(db.is_available())

            -- record should also be a no-op now
            current_time = 3000
            db.record("test", "post_failure_item")

            -- No stale data returns — read_scores still empty
            current_time = 3000
            local scores_stale_check = db.read_scores("test", { "pre_failure_item", "post_failure_item" })
            assert.are.same({}, scores_stale_check)

            -- Corrupt file untouched
            assert.are.same({ "{not json" }, vim.fn.readfile(corrupt_path))

            cleanup_path(corrupt_path)
        end)
    end)

    describe("is_available()", function()
        it("returns true by default", function()
            assert.is_true(db.is_available())
        end)

        it("returns false after entering no-op mode", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, path)
            db.read_scores("p", { "k" })
            assert.is_false(db.is_available())
        end)
    end)
end)
