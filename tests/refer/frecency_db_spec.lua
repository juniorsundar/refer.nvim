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

local function configure_json(path)
    db.configure { db_path = path }
end

describe("refer.frecency.db", function()
    local path

    before_each(function()
        path = temp_path()
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
            db.record("test_provider", "item1", {
                clock_fn = function()
                    return 1000
                end,
            })

            assert.is_true(vim.fn.filereadable(path) == 1)
            local store = read_json(path)
            assert.are.equal(1, store.version)
            assert.is_table(store.providers.test_provider.item1)
        end)

        it("accepts configurable db_path", function()
            db.record("p", "k", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_true(vim.fn.filereadable(path) == 1)
        end)

        it("starts from an empty store when the file is missing", function()
            local scores = db.read_scores("p", { "missing" }, {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.are.same({}, scores)
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)
    end)

    describe("record()", function()
        it("inserts a new record with count=1 and a timestamp", function()
            local fixed_time = 1000000
            db.record("buffers", "item_a", {
                clock_fn = function()
                    return fixed_time
                end,
            })

            local store = read_json(path)
            local record = store.providers.buffers.item_a
            assert.are.equal(1, record.selected_count)
            assert.are.equal(fixed_time, record.last_selected_at)

            local scores = db.read_scores("buffers", { "item_a" }, {
                clock_fn = function()
                    return fixed_time + 3600
                end,
            })
            assert.are.equal(0.5, scores.item_a)
        end)

        it("increments count and updates timestamp on repeat selections", function()
            local t0 = 1000000
            db.record("buffers", "item_a", {
                clock_fn = function()
                    return t0
                end,
            })
            db.record("buffers", "item_a", {
                clock_fn = function()
                    return t0 + 100
                end,
            })

            local store = read_json(path)
            local record = store.providers.buffers.item_a
            assert.are.equal(2, record.selected_count)
            assert.are.equal(t0 + 100, record.last_selected_at)

            local scores = db.read_scores("buffers", { "item_a" }, {
                clock_fn = function()
                    return t0 + 100
                end,
            })
            assert.are.equal(2, scores.item_a)
        end)

        it("count accumulates across many selections", function()
            local t = 1000000
            for _ = 1, 10 do
                db.record("test", "popular", {
                    clock_fn = function()
                        return t
                    end,
                })
                t = t + 100
            end

            local scores = db.read_scores("test", { "popular" }, {
                clock_fn = function()
                    return t
                end,
            })
            assert.are.equal(10, scores.popular)
        end)

        it("is a no-op when provider is nil", function()
            db.record(nil, "item", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when provider is empty string", function()
            db.record("", "item", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when item_key is nil", function()
            db.record("p", nil, {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)

        it("is a no-op when item_key is empty string", function()
            db.record("p", "", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_false(vim.fn.filereadable(path) == 1)
        end)
    end)

    describe("read_scores()", function()
        it("returns scores for multiple item keys", function()
            local now = 1000000
            db.record("files", "file_a", {
                clock_fn = function()
                    return now
                end,
            })
            db.record("files", "file_b", {
                clock_fn = function()
                    return now - 86400
                end,
            })
            db.record("files", "file_c", {
                clock_fn = function()
                    return now - 604800
                end,
            })

            local scores = db.read_scores("files", { "file_a", "file_b", "file_c" }, {
                clock_fn = function()
                    return now
                end,
            })

            assert.are.equal(1, scores.file_a)
            assert.are.equal(0.25, scores.file_b)
            assert.are.equal(0.125, scores.file_c)
        end)

        it("keys without records are absent from the result map", function()
            local now = 1000000
            db.record("p", "exists", {
                clock_fn = function()
                    return now
                end,
            })

            local scores = db.read_scores("p", { "exists", "missing" }, {
                clock_fn = function()
                    return now
                end,
            })
            assert.is_not_nil(scores.exists)
            assert.is_nil(scores.missing)
        end)

        it("returns empty map for empty item_keys", function()
            local scores = db.read_scores("p", {}, {
                clock_fn = function()
                    return 0
                end,
            })
            assert.are.same({}, scores)
        end)

        it("returns empty map when provider is nil", function()
            local scores = db.read_scores(nil, { "k" })
            assert.are.same({}, scores)
        end)

        it("providers are isolated", function()
            local t = 1000000
            db.record("buffers", "item", {
                clock_fn = function()
                    return t
                end,
            })
            db.record("files", "item", {
                clock_fn = function()
                    return t - 3600
                end,
            })

            local buf_scores = db.read_scores("buffers", { "item" }, {
                clock_fn = function()
                    return t
                end,
            })
            local file_scores = db.read_scores("files", { "item" }, {
                clock_fn = function()
                    return t
                end,
            })

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

            local scores = db.read_scores("p", { "stale" }, {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.are.equal(1, scores.stale) -- 8 / divisor 8
        end)
    end)

    describe("JSON failure handling", function()
        it("enters no-op mode on corrupt JSON and leaves file untouched", function()
            vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, path)

            local scores = db.read_scores("p", { "k" }, {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.are.same({}, scores)
            assert.is_false(db.is_available())
            assert.are.same({ "{not json" }, vim.fn.readfile(path))

            db.record("p", "k", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.are.same({ "{not json" }, vim.fn.readfile(path))
        end)

        it("enters no-op mode when atomic rename fails", function()
            local dir_path = temp_path "_as_dir"
            path = dir_path
            vim.fn.mkdir(path, "p")
            db._reset()
            configure_json(path)

            db.record("p", "k", {
                clock_fn = function()
                    return 1000
                end,
            })
            assert.is_false(db.is_available())
            assert.is_true(vim.fn.isdirectory(path) == 1)
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
