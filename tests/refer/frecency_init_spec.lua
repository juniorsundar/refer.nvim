local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

local function temp_path()
    return vim.fn.tempname() .. "_init_test.json"
end

local active_path
local current_time = 0

local function setup_frecency(opts)
    local cfg = vim.deepcopy(opts or {})
    active_path = cfg.db_path or temp_path()
    cfg.db_path = active_path
    if cfg.clock_fn == nil then
        cfg.clock_fn = function()
            return current_time
        end
    end
    frecency.configure(cfg)
end

local function reset()
    current_time = 0
    if active_path then
        vim.fn.delete(active_path, "rf")
        vim.fn.delete(vim.fn.fnamemodify(active_path, ":h"), "rf")
        active_path = nil
    end
    db._reset()
    frecency.configure {
        enabled = true,
        buckets = false,
        neighborhood_size = 10,
    }
end

describe("refer.frecency (init)", function()
    before_each(function()
        reset()
    end)

    after_each(function()
        reset()
    end)

    describe("public API", function()
        it("exposes configure", function()
            assert.is_function(frecency.configure)
        end)

        it("exposes record", function()
            assert.is_function(frecency.record)
        end)

        it("exposes score", function()
            assert.is_function(frecency.score)
        end)

        it("exposes reorder", function()
            assert.is_function(frecency.reorder)
        end)

        it("exposes resolve_key", function()
            assert.is_function(frecency.resolve_key)
        end)

        it("exposes is_available", function()
            assert.is_function(frecency.is_available)
        end)

        it("exposes status", function()
            assert.is_function(frecency.status)
        end)

        it("exposes cleanup", function()
            assert.is_function(frecency.cleanup)
        end)
    end)

    describe("configure()", function()
        it("accepts db_path option", function()
            setup_frecency { db_path = temp_path() }
            current_time = 1000
            frecency.record("p", "k")
            assert.is_true(vim.fn.filereadable(active_path) == 1)
        end)

        it("accepts buckets option", function()
            setup_frecency {
                buckets = { { max_age = 60, divisor = 1 }, { max_age = math.huge, divisor = 10 } },
            }
            local t = 1000
            current_time = t
            frecency.record("p", "item")
            current_time = t + 120
            local scores = frecency.score("p", { "item" })
            assert.are.equal(0.1, scores.item)
        end)

        it("accepts neighborhood_size option", function()
            setup_frecency()
            frecency.configure { neighborhood_size = 5 }
            assert.is_true(true)
        end)

        it("accepts clock_fn option", function()
            local called = false
            local test_clock = function()
                called = true
                return 42
            end
            setup_frecency { clock_fn = test_clock }
            frecency.record("p", "k")
            assert.is_true(called)
        end)
    end)

    describe("record()", function()
        it("records a selection via db.record", function()
            setup_frecency()
            local t = 1000000
            current_time = t
            frecency.record("test_provider", "test_key")

            current_time = t
            local scores = frecency.score("test_provider", { "test_key" })
            assert.are.equal(1, scores.test_key)
        end)

        it("is a no-op when provider is nil", function()
            setup_frecency()
            current_time = 1000
            frecency.record(nil, "key")
            assert.is_false(vim.fn.filereadable(active_path) == 1)
        end)

        it("is a no-op when item_key is nil", function()
            setup_frecency()
            frecency.record("p", nil)
            assert.is_false(vim.fn.filereadable(active_path) == 1)
        end)
    end)

    describe("score()", function()
        it("returns a map of item_key → frecency_score", function()
            setup_frecency()
            local t = 1000000
            current_time = t
            frecency.record("p", "a")
            current_time = t - 3600
            frecency.record("p", "b")

            current_time = t
            local scores = frecency.score("p", { "a", "b" })
            assert.are.equal(1, scores.a)
            assert.are.equal(0.5, scores.b)
        end)

        it("keys without records are absent from the result", function()
            setup_frecency()
            local t = 1000000
            current_time = t
            frecency.record("p", "exists")

            current_time = t
            local scores = frecency.score("p", { "exists", "missing" })
            assert.is_not_nil(scores.exists)
            assert.is_nil(scores.missing)
        end)

        it("returns empty table for empty item_keys", function()
            setup_frecency()
            current_time = 1000
            local scores = frecency.score("p", {})
            assert.are.same({}, scores)
        end)

        it("returns empty table when provider is nil", function()
            setup_frecency()
            local scores = frecency.score(nil, { "key" })
            assert.are.same({}, scores)
        end)
    end)

    describe("reorder()", function()
        it("empty-query sorts items entirely by frecency score", function()
            setup_frecency()
            local t = 1000000

            current_time = t - 604800
            frecency.record("p", "a")
            current_time = t
            frecency.record("p", "b")
            current_time = t - 86400
            frecency.record("p", "c")

            local items = { { text = "a" }, { text = "b" }, { text = "c" } }
            current_time = t
            local result = frecency.reorder("p", items)

            assert.are.same("b", result[1].text)
            assert.are.same("c", result[2].text)
            assert.are.same("a", result[3].text)
        end)

        it("reorders items within score neighborhoods by frecency", function()
            setup_frecency()
            local t = 1000000

            current_time = t
            frecency.record("p", "b")
            current_time = t - 604800
            frecency.record("p", "a")

            local items = { { text = "a" }, { text = "b" }, { text = "c" }, { text = "d" } }
            current_time = t
            local frec_scores = frecency.score("p", { "a", "b", "c", "d" })
            local result = frecency.reorder("p", items, {
                scores = { a = 100, b = 100, c = 10, d = 10 },
                frecency_scores = frec_scores,
            })

            assert.are.same("b", result[1].text)
            assert.are.same("a", result[2].text)
            assert.are.same("c", result[3].text)
            assert.are.same("d", result[4].text)
        end)

        it("returns items unchanged when scores is nil and no records exist", function()
            setup_frecency()
            local items = { { text = "a" }, { text = "b" } }
            local result = frecency.reorder("p", items, {})
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
        end)

        it("returns items unchanged when provider is nil", function()
            setup_frecency()
            local items = { { text = "a" }, { text = "b" } }
            local result = frecency.reorder(nil, items, { frecency_scores = { b = 10 } })
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
        end)

        it("returns empty table for empty items", function()
            setup_frecency()
            local result = frecency.reorder("p", {}, { scores = { a = 10 } })
            assert.are.same({}, result)
        end)

        it("returns empty table for nil items", function()
            setup_frecency()
            local result = frecency.reorder("p", nil, { scores = { a = 10 } })
            assert.are.same({}, result)
        end)

        it("returns items unchanged after no-op mode even with supplied frecency_scores", function()
            setup_frecency()
            vim.fn.mkdir(vim.fn.fnamemodify(active_path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, active_path)
            frecency.score("p", { "a" })
            assert.is_false(frecency.is_available())

            local items = { { text = "a" }, { text = "b" } }
            local result = frecency.reorder("p", items, {
                scores = { a = 100, b = 100 },
                frecency_scores = { b = 10 },
            })

            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
        end)
    end)

    describe("resolve_key()", function()
        it("delegates to score.resolve_key with text strategy", function()
            local key = frecency.resolve_key({ text = "hello" }, "text")
            assert.are.equal("hello", key)
        end)

        it("delegates to score.resolve_key with filepath strategy", function()
            local key = frecency.resolve_key({ text = "label", data = { filename = "/tmp/test.lua" } }, "filepath")
            assert.are.equal(vim.fn.fnamemodify("/tmp/test.lua", ":p"), key)
        end)

        it("delegates to score.resolve_key with custom function", function()
            local key = frecency.resolve_key({ text = "label", data = { id = "42" } }, function(item)
                return "custom_" .. (item.data and item.data.id or "")
            end)
            assert.are.equal("custom_42", key)
        end)
    end)

    describe("is_available()", function()
        it("returns true before persistence failure", function()
            setup_frecency()
            assert.is_true(frecency.is_available())
        end)

        it("returns false after persistence failure", function()
            local bad_path = temp_path() .. "_dir"
            active_path = bad_path
            vim.fn.mkdir(bad_path, "p")
            frecency.configure { db_path = bad_path }
            frecency.record("p", "k")
            assert.is_false(frecency.is_available())
        end)
    end)

    describe("status()", function()
        it("returns disabled shape when globally disabled", function()
            local test_path = temp_path()
            active_path = test_path
            frecency.configure { enabled = false, db_path = test_path }

            local s = frecency.status()
            assert.is_table(s)
            assert.is_false(s.enabled)
            assert.is_false(s.store_available)
            assert.is_false(s.active)
            assert.is_false(s.no_op)
            assert.are.equal("disabled by config", s.reason)
            assert.are.equal(test_path, s.db_path)
        end)

        it("returns active shape when store is available and enabled", function()
            local test_path = temp_path()
            active_path = test_path
            frecency.configure { enabled = true, db_path = test_path }

            local s = frecency.status()
            assert.is_true(s.enabled)
            assert.is_true(s.store_available)
            assert.is_true(s.active)
            assert.is_false(s.no_op)
            assert.is_nil(s.reason)
            assert.are.equal(test_path, s.db_path)
        end)

        it("returns no-op shape with reason after corrupt JSON store", function()
            local test_path = temp_path()
            active_path = test_path
            -- Write corrupt JSON to trigger no-op mode
            vim.fn.mkdir(vim.fn.fnamemodify(test_path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, test_path)
            frecency.configure { enabled = true, db_path = test_path }

            -- Trigger read failure
            frecency.score("p", { "key" })

            local s = frecency.status()
            assert.is_true(s.enabled)
            assert.is_false(s.store_available)
            assert.is_false(s.active)
            assert.is_true(s.no_op)
            assert.is_not_nil(s.reason)
            assert.are.equal(test_path, s.db_path)
        end)

        it("returns no-op shape with reason after write failure", function()
            local test_path = temp_path() .. "_dir"
            active_path = test_path
            -- Create a directory at the path to cause write failure (rename fails)
            vim.fn.mkdir(test_path, "p")
            frecency.configure { enabled = true, db_path = test_path }

            -- Trigger write failure
            frecency.record("p", "key")

            local s = frecency.status()
            assert.is_true(s.enabled)
            assert.is_false(s.store_available)
            assert.is_false(s.active)
            assert.is_true(s.no_op)
            assert.is_not_nil(s.reason)
            assert.are.equal(test_path, s.db_path)

            -- Cleanup
            vim.fn.delete(test_path, "rf")
        end)

        it("reports disabled by config after prior no-op mode", function()
            local test_path = temp_path()
            active_path = test_path
            vim.fn.mkdir(vim.fn.fnamemodify(test_path, ":h"), "p")
            vim.fn.writefile({ "{not json" }, test_path)
            frecency.configure { enabled = true, db_path = test_path }
            frecency.score("p", { "key" })
            assert.is_false(frecency.is_available())

            frecency.configure { enabled = false }

            local s = frecency.status()
            assert.is_false(s.enabled)
            assert.is_false(s.store_available)
            assert.is_false(s.active)
            assert.is_false(s.no_op)
            assert.are.equal("disabled by config", s.reason)
            assert.are.equal(test_path, s.db_path)
        end)
    end)

    describe("global disable", function()
        it("record() is a no-op and does not create store files", function()
            local test_path = temp_path()
            active_path = test_path
            frecency.configure { enabled = false, db_path = test_path }

            frecency.record("p", "k")
            assert.is_false(vim.fn.filereadable(test_path) == 1)
        end)

        it("score() returns empty table when globally disabled", function()
            local test_path = temp_path()
            active_path = test_path
            frecency.configure { enabled = false, db_path = test_path }

            -- First record something to ensure there IS data in the store
            frecency.configure { enabled = true, db_path = test_path }
            frecency.record("p", "key")
            -- Then disable
            frecency.configure { enabled = false }

            local scores = frecency.score("p", { "key" })
            assert.are.same({}, scores)
        end)

        it("reorder() returns items unchanged when globally disabled", function()
            local test_path = temp_path()
            active_path = test_path
            frecency.configure { enabled = true, db_path = test_path }
            -- Record to create a frecency score for "b"
            frecency.record("p", "b")
            -- Then disable
            frecency.configure { enabled = false }

            -- Same fuzzy scores → same neighborhood, frecency would normally promote "b"
            local items = { { text = "a" }, { text = "b" } }
            local result = frecency.reorder("p", items, {
                scores = { a = 100, b = 100 },
            })
            -- With global disable, reorder should NOT apply frecency → original order
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
        end)
    end)

    describe("encapsulation", function()
        it("does not expose internal modules directly", function()
            assert.is_nil(rawget(frecency, "_db"))
            assert.is_nil(rawget(frecency, "_score"))
        end)
    end)
end)
