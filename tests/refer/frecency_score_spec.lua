local score = require "refer.frecency.score"

-- Helper: create a ReferItem { text, data }
local function item(text, data)
    return { text = text, data = data }
end

describe("refer.frecency.score", function()
    -- ── Bucket Calculation ──────────────────────────────────────────

    describe("compute()", function()
        it("last hour: age < 3600 → divisor 1", function()
            -- count=10, age=0 (just now) → 10/1 = 10
            assert.are.equal(10, score.compute(10, 0))
            -- count=10, age=3599 → 10/1 = 10
            assert.are.equal(10, score.compute(10, 3599))
        end)

        it("last day: age in [3600, 86400) → divisor 2", function()
            assert.are.equal(5, score.compute(10, 3600))
            assert.are.equal(5, score.compute(10, 86399))
        end)

        it("last week: age in [86400, 604800) → divisor 4", function()
            assert.are.equal(2.5, score.compute(10, 86400))
            assert.are.equal(2.5, score.compute(10, 604799))
        end)

        it("older: age >= 604800 → divisor 8", function()
            assert.are.equal(1.25, score.compute(10, 604800))
            assert.are.equal(0.125, score.compute(1, 10000000))
        end)

        it("negative age (future timestamp) → treated as bucket 0 (divisor 1)", function()
            -- Future timestamps are treated as most recent
            assert.are.equal(10, score.compute(10, -100))
            assert.are.equal(5, score.compute(5, -3600))
        end)

        it("zero count → score is 0", function()
            assert.are.equal(0, score.compute(0, 0))
            assert.are.equal(0, score.compute(0, 86400))
        end)

        it("zero age → divisor 1", function()
            assert.are.equal(1, score.compute(1, 0))
        end)

        it("accepts custom bucket configuration", function()
            local custom_buckets = {
                { max_age = 60, divisor = 1 },
                { max_age = math.huge, divisor = 10 },
            }
            -- age=30 → bucket 0, divisor 1 → 5/1 = 5
            assert.are.equal(5, score.compute(5, 30, custom_buckets))
            -- age=120 → bucket 1, divisor 10 → 5/10 = 0.5
            assert.are.equal(0.5, score.compute(5, 120, custom_buckets))
        end)

        it("count is fractional → score is fractional", function()
            -- Explicitly verify floating-point behavior
            local result = score.compute(3, 3600) -- divisor 2
            assert.are.equal(1.5, result)
        end)
    end)

    -- ── Key Strategy Resolution ─────────────────────────────────────

    describe("resolve_key()", function()
        it('"text" strategy returns item.text', function()
            assert.are.equal("hello", score.resolve_key(item "hello", "text"))
            assert.are.equal("world", score.resolve_key(item("world", { filename = "/x" }), "text"))
        end)

        it('"filepath" strategy normalizes filename to absolute path', function()
            local result = score.resolve_key(item("/tmp/file.txt", { filename = "/tmp/file.txt" }), "filepath")
            assert.are.equal(vim.fn.fnamemodify("/tmp/file.txt", ":p"), result)
        end)

        it('"filepath" strategy normalizes relative paths to absolute', function()
            local expected = vim.fn.fnamemodify("relative/path.lua", ":p")
            local result = score.resolve_key(item("display text", { filename = "relative/path.lua" }), "filepath")
            assert.are.equal(expected, result)
        end)

        it('"filepath" strategy falls back to "text" when data.filename is absent', function()
            local result = score.resolve_key(item("fallback text", {}), "filepath")
            assert.are.equal("fallback text", result)
        end)

        it('"filepath" strategy falls back to "text" when data is nil', function()
            local result = score.resolve_key(item("fallback text", nil), "filepath")
            assert.are.equal("fallback text", result)
        end)

        it('"filepath_with_lnum" concatenates absolute path and line number', function()
            local result =
                score.resolve_key(item("label", { filename = "/tmp/file.lua", lnum = 42 }), "filepath_with_lnum")
            local expected = vim.fn.fnamemodify("/tmp/file.lua", ":p") .. ":42"
            assert.are.equal(expected, result)
        end)

        it('"filepath_with_lnum" falls back to "text" when data.filename is absent', function()
            local result = score.resolve_key(item("fallback", { lnum = 42 }), "filepath_with_lnum")
            assert.are.equal("fallback", result)
        end)

        it('"filepath_with_lnum" falls back to "text" when data.lnum is absent', function()
            local result = score.resolve_key(item("fallback", { filename = "/tmp/x.lua" }), "filepath_with_lnum")
            assert.are.equal("fallback", result)
        end)

        it("two items with same text but different filenames resolve differently under filepath", function()
            local key1 = score.resolve_key(item("a", { filename = "/x/a.lua" }), "filepath")
            local key2 = score.resolve_key(item("a", { filename = "/y/a.lua" }), "filepath")
            assert.are.not_equal(key1, key2)
        end)

        it("custom key function receives item and returns key", function()
            local custom = function(it)
                return it.text .. "_custom"
            end
            assert.are.equal("hello_custom", score.resolve_key(item "hello", custom))
        end)

        it("custom key function receives item.data", function()
            local custom = function(it)
                return (it.data and it.data.id) or it.text
            end
            assert.are.equal("xyz", score.resolve_key(item("ignored", { id = "xyz" }), custom))
        end)

        it("custom key function returning nil falls back to text strategy", function()
            local custom = function()
                return nil
            end
            local result = score.resolve_key(item("fallback", { id = "123" }), custom)
            assert.are.equal("fallback", result)
        end)

        it("returns nil when item is nil", function()
            assert.is_nil(score.resolve_key(nil, "text"))
        end)

        it("returns nil when strategy is nil and item has no text", function()
            -- nil strategy: default to text → item has no text → returns nil
            assert.is_nil(score.resolve_key({}, nil))
        end)

        it("nil strategy defaults to text strategy", function()
            local result = score.resolve_key(item "hello", nil)
            assert.are.equal("hello", result)
        end)

        it("unknown strategy string falls back to text", function()
            local result = score.resolve_key(item "hello", "nonexistent")
            assert.are.equal("hello", result)
        end)
    end)

    -- ── Neighborhood Reordering ──────────────────────────────────────

    describe("reorder()", function()
        it("returns items unchanged when opts.scores is nil", function()
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, { frecency_scores = { a = 10, b = 5 } })
            assert.are.same(3, #result)
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
            assert.are.same("c", result[3].text)
        end)

        it("returns items unchanged when opts.scores is empty", function()
            local items = { item "a", item "b" }
            local result = score.reorder(items, { scores = {} })
            assert.are.same(2, #result)
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
        end)

        it("returns empty table for empty items", function()
            local result = score.reorder({}, { scores = { a = 100 } })
            assert.are.same({}, result)
        end)

        it("reorders items within same fuzzy score neighborhood by frecency", function()
            -- Items a, b, c have same fuzzy score → within same neighborhood
            -- Frecency: b=100, a=10, c=5 → reorder to b, a, c
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50 },
                frecency_scores = { a = 10, b = 100, c = 5 },
            })
            assert.are.same(3, #result)
            assert.are.same("b", result[1].text) -- highest frecency
            assert.are.same("a", result[2].text)
            assert.are.same("c", result[3].text) -- lowest frecency
        end)

        it("preserves original order when frecency scores are equal within neighborhood", function()
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50 },
                frecency_scores = { a = 10, b = 10, c = 10 },
            })
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
            assert.are.same("c", result[3].text)
        end)

        it("items without frecency score appear after scored items in same neighborhood", function()
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50 },
                frecency_scores = { b = 10 }, -- only b has a score
            })
            -- b (has score) comes first, then a, c in original order
            assert.are.same("b", result[1].text)
            assert.are.same("a", result[2].text)
            assert.are.same("c", result[3].text)
        end)

        it("items without frecency score preserve original relative order", function()
            local items = { item "a", item "b", item "c", item "d" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50, d = 50 },
                frecency_scores = { d = 100 }, -- only d has score
            })
            -- d (scored) first, then a, b, c in original order
            assert.are.same("d", result[1].text)
            assert.are.same("a", result[2].text)
            assert.are.same("b", result[3].text)
            assert.are.same("c", result[4].text)
        end)

        it("groups items by fuzzy score and only reorders within each neighborhood", function()
            -- Two neighborhoods: {a,b} with score 100, {c,d} with score 10
            -- Within each neighborhood, reorder by frecency
            local items = { item "a", item "b", item "c", item "d" }
            local result = score.reorder(items, {
                scores = { a = 100, b = 100, c = 10, d = 10 },
                frecency_scores = { a = 5, b = 50, c = 100, d = 1 },
            })
            -- Neighborhood 1 (score~100): b (50) then a (5)
            -- Neighborhood 2 (score~10): c (100) then d (1)
            -- Overall: b, a, c, d
            assert.are.same("b", result[1].text)
            assert.are.same("a", result[2].text)
            assert.are.same("c", result[3].text)
            assert.are.same("d", result[4].text)
        end)

        it("uses neighborhood_size from opts to control group size", function()
            -- 6 items, all same fuzzy score, neighborhood_size=2
            -- Should reorder in groups of 2
            local items = { item "a", item "b", item "c", item "d", item "e", item "f" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50, d = 50, e = 50, f = 50 },
                frecency_scores = { a = 1, b = 10, c = 2, d = 20, e = 3, f = 30 },
                neighborhood_size = 2,
            })
            -- Group 1 {a,b}: b(10), a(1) → b, a
            -- Group 2 {c,d}: d(20), c(2) → d, c
            -- Group 3 {e,f}: f(30), e(3) → f, e
            -- Overall: b, a, d, c, f, e
            assert.are.same("b", result[1].text)
            assert.are.same("a", result[2].text)
            assert.are.same("d", result[3].text)
            assert.are.same("c", result[4].text)
            assert.are.same("f", result[5].text)
            assert.are.same("e", result[6].text)
        end)

        it("default neighborhood_size is 10", function()
            -- 12 items, same fuzzy score, default neighborhood=10
            -- First 10 reordered, last 2 as their own group
            local items = {}
            local scores = {}
            local frecency = {}
            for i = 1, 12 do
                local t = "item" .. i
                table.insert(items, item(t))
                scores[t] = 50
                frecency[t] = 13 - i -- descending: item1=12, item12=1
            end
            local result = score.reorder(items, {
                scores = scores,
                frecency_scores = frecency,
            })
            -- First 10 reordered by descending frecency: item12(1), item11(2), ..., item3(10)?? No wait
            -- item1=12, item2=11, item3=10, item4=9, item5=8, item6=7, item7=6, item8=5, item9=4, item10=3, item11=2, item12=1
            -- Group 1 (10 items: item1-item10): reorder by frecency desc: item1(12), item2(11), item3(10), ... item10(3)
            -- Group 2 (2 items: item11, item12): reorder by frecency desc: item11(2), item12(1)
            assert.are.same(12, #result)
            -- First group (positions 1-10): should be item1-item10 since they have descending frecency and that IS the sorted order
            -- Wait, they already are in descending frecency order: item1=12, item2=11, ..., item10=3
            -- So they should stay the same
            for i = 1, 10 do
                assert.are.same("item" .. i, result[i].text)
            end
            -- Second group: item11=2, item12=1 → sorted desc: item11, item12
            assert.are.same("item11", result[11].text)
            assert.are.same("item12", result[12].text)
        end)

        it("skips items not present in opts.scores", function()
            -- item 'c' is not in scores → it's skipped during reorder (should still appear)
            -- Actually: items not in scores should be treated as having no fuzzy score
            -- They still get included, placed after scored items within their neighborhood
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50 }, -- c missing
                frecency_scores = { a = 1, b = 10, c = 100 },
            })
            -- a, b in same neighborhood → reorder: b(10), a(1)
            -- c has no fuzzy score → not grouped with a,b → treated as its own un-scored item
            -- c should appear after a,b in original position? Or at end?
            -- Per spec: "When opts.scores is present, items are grouped into neighborhoods of similar fuzzy score"
            -- Items without fuzzy score are not in any neighborhood → they're after all scored items
            -- Actually, let me check: c has text 'c' but it's not in scores
            -- For items not in scores, they should be treated as a separate group after scored items
            -- and within that group, reorder by frecency (since they still can have frecency)
            -- Actually wait: re-read the spec: "When items have no Frecency score, preserve their original order after scored items."
            -- And: "When scores are equal within a neighborhood, preserve original order."
            -- Items not in opts.scores have no fuzzy score → they get placed after all scored items,
            -- preserving original relative order among themselves.
            assert.are.same(3, #result)
            assert.are.same("b", result[1].text) -- highest frecency in neighborhood
            assert.are.same("a", result[2].text)
            assert.are.same("c", result[3].text) -- un-scored, after scored items
        end)

        it("empty-query: score.reorder returns unchanged when scores is nil (caller uses sort_by_frecency)", function()
            local items = { item "a", item "b", item "c" }
            local result = score.reorder(items, {
                frecency_scores = { a = 1, b = 100, c = 50 },
            })
            -- scores is nil → items returned unchanged by score.reorder
            -- (init.lua handles empty-query by calling sort_by_frecency instead)
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
            assert.are.same("c", result[3].text)
        end)

        it("items with no frecency AND no fuzzy score appear at end in original order", function()
            local items = { item "x", item "y", item "z" }
            local result = score.reorder(items, {
                scores = { x = 10, y = 10, z = 10 },
                -- no frecency scores at all
            })
            -- All have same fuzzy score (same neighborhood), no frecency → original order
            assert.are.same("x", result[1].text)
            assert.are.same("y", result[2].text)
            assert.are.same("z", result[3].text)
        end)

        it("mixed: some items with frecency, some without, in same neighborhood", function()
            local items = { item "a", item "b", item "c", item "d" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50, d = 50 },
                frecency_scores = { c = 100, b = 50 },
            })
            -- Same neighborhood. c(100) first, b(50) second, then a, d in original order
            assert.are.same("c", result[1].text)
            assert.are.same("b", result[2].text)
            assert.are.same("a", result[3].text)
            assert.are.same("d", result[4].text)
        end)
    end)

    -- ── Full Sort by Frecency ───────────────────────────────────────

    describe("sort_by_frecency()", function()
        it("sorts items entirely by frecency score descending", function()
            local items = { item "a", item "b", item "c" }
            local result = score.sort_by_frecency(items, {
                a = 1,
                b = 100,
                c = 50,
            })
            assert.are.same("b", result[1].text)
            assert.are.same("c", result[2].text)
            assert.are.same("a", result[3].text)
        end)

        it("preserves original order when frecency scores are equal", function()
            local items = { item "a", item "b", item "c" }
            local result = score.sort_by_frecency(items, {
                a = 10,
                b = 10,
                c = 10,
            })
            assert.are.same("a", result[1].text)
            assert.are.same("b", result[2].text)
            assert.are.same("c", result[3].text)
        end)

        it("items without frecency scores appear after scored items in original order", function()
            local items = { item "a", item "b", item "c", item "d" }
            local result = score.sort_by_frecency(items, {
                b = 100,
                d = 1,
            })
            -- Scored: b(100), d(1) → b, d
            -- Unscored: a, c (original order)
            -- Final: b, d, a, c
            assert.are.same("b", result[1].text)
            assert.are.same("d", result[2].text)
            assert.are.same("a", result[3].text)
            assert.are.same("c", result[4].text)
        end)

        it("returns items unchanged when frecency_scores is empty", function()
            local items = { item "x", item "y" }
            local result = score.sort_by_frecency(items, {})
            assert.are.same("x", result[1].text)
            assert.are.same("y", result[2].text)
        end)

        it("returns empty for empty items", function()
            local result = score.sort_by_frecency({}, { a = 10 })
            assert.are.same({}, result)
        end)
    end)

    -- ── Edge Cases ──────────────────────────────────────────────────

    describe("edge cases", function()
        it("reorder with items that are strings (not tables)", function()
            -- Robustness: items passed as raw strings should be handled
            local items = { "a", "b", "c" }
            local result = score.reorder(items, {
                scores = { a = 50, b = 50, c = 50 },
                frecency_scores = { a = 1, b = 100, c = 5 },
            })
            -- b (100), c (5), a (1) within same neighborhood
            assert.are.same("b", result[1])
            assert.are.same("c", result[2])
            assert.are.same("a", result[3])
        end)
    end)
end)
