local frecency = require "refer.frecency"
local db = require "refer.frecency.db"

local function temp_path()
    return vim.fn.tempname() .. "_init_test.json"
end

local active_path

local function setup_frecency(opts)
    opts = opts or {}
    active_path = opts.db_path or temp_path()
    opts.db_path = active_path
    frecency.configure(opts)
end

local function reset()
    if active_path then
        vim.fn.delete(active_path, "rf")
        vim.fn.delete(vim.fn.fnamemodify(active_path, ":h"), "rf")
        active_path = nil
    end
    db._reset()
    frecency.configure {
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
    end)

    describe("configure()", function()
        it("accepts db_path option", function()
            setup_frecency { db_path = temp_path() }
            frecency.record("p", "k")
            assert.is_true(vim.fn.filereadable(active_path) == 1)
        end)

        it("accepts buckets option", function()
            setup_frecency {
                buckets = { { max_age = 60, divisor = 1 }, { max_age = math.huge, divisor = 10 } },
            }
            local t = 1000
            frecency.record("p", "item", {
                clock_fn = function()
                    return t
                end,
            })
            local scores = frecency.score("p", { "item" }, {
                clock_fn = function()
                    return t + 120
                end,
            })
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
            frecency.record("test_provider", "test_key", {
                clock_fn = function()
                    return t
                end,
            })

            local scores = frecency.score("test_provider", { "test_key" }, {
                clock_fn = function()
                    return t
                end,
            })
            assert.are.equal(1, scores.test_key)
        end)

        it("is a no-op when provider is nil", function()
            setup_frecency()
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
            frecency.record("p", "a", {
                clock_fn = function()
                    return t
                end,
            })
            frecency.record("p", "b", {
                clock_fn = function()
                    return t - 3600
                end,
            })

            local scores = frecency.score("p", { "a", "b" }, {
                clock_fn = function()
                    return t
                end,
            })
            assert.are.equal(1, scores.a)
            assert.are.equal(0.5, scores.b)
        end)

        it("keys without records are absent from the result", function()
            setup_frecency()
            local t = 1000000
            frecency.record("p", "exists", {
                clock_fn = function()
                    return t
                end,
            })

            local scores = frecency.score("p", { "exists", "missing" }, {
                clock_fn = function()
                    return t
                end,
            })
            assert.is_not_nil(scores.exists)
            assert.is_nil(scores.missing)
        end)

        it("returns empty table for empty item_keys", function()
            setup_frecency()
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

            frecency.record("p", "a", {
                clock_fn = function()
                    return t - 604800
                end,
            })
            frecency.record("p", "b", {
                clock_fn = function()
                    return t
                end,
            })
            frecency.record("p", "c", {
                clock_fn = function()
                    return t - 86400
                end,
            })

            local items = { { text = "a" }, { text = "b" }, { text = "c" } }
            local result = frecency.reorder("p", items, {
                clock_fn = function()
                    return t
                end,
            })

            assert.are.same("b", result[1].text)
            assert.are.same("c", result[2].text)
            assert.are.same("a", result[3].text)
        end)

        it("reorders items within score neighborhoods by frecency", function()
            setup_frecency()
            local t = 1000000

            frecency.record("p", "b", {
                clock_fn = function()
                    return t
                end,
            })
            frecency.record("p", "a", {
                clock_fn = function()
                    return t - 604800
                end,
            })

            local items = { { text = "a" }, { text = "b" }, { text = "c" }, { text = "d" } }
            local frec_scores = frecency.score("p", { "a", "b", "c", "d" }, {
                clock_fn = function()
                    return t
                end,
            })
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

    describe("encapsulation", function()
        it("does not expose internal modules directly", function()
            assert.is_nil(rawget(frecency, "_db"))
            assert.is_nil(rawget(frecency, "_score"))
        end)
    end)
end)
