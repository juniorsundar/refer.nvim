local fuzzy = require "refer.fuzzy"
local blink = require "refer.blink"
local stub = require "luassert.stub"

describe("refer.fuzzy", function()
    stub(blink, "is_available", false)

    describe("_simple_fuzzy_score", function()
        local score = fuzzy._simple_fuzzy_score

        it("returns 0 for empty pattern", function()
            assert.are.same(0, score("anything", ""))
        end)

        it("returns nil when pattern char not found", function()
            assert.is_nil(score("abc", "z"))
        end)

        it("returns nil when string is shorter than pattern", function()
            assert.is_nil(score("ab", "abc"))
        end)

        it("scores exact match higher than distant match", function()
            local exact = score("abc", "abc")
            local distant = score("a--b--c", "abc")
            assert.is_not_nil(exact)
            assert.is_not_nil(distant)
            assert.is_true(exact > distant)
        end)

        it("awards word boundary bonus", function()
            local boundary = score("foo-bar", "b")
            local no_boundary = score("foobar", "b")
            assert.is_not_nil(boundary)
            assert.is_not_nil(no_boundary)
            assert.is_true(boundary > no_boundary)
        end)

        it("awards camelCase bonus", function()
            local camel = score("fooBar", "B")
            local no_camel = score("foobar", "b")
            assert.is_not_nil(camel)
            assert.is_not_nil(no_camel)
            assert.is_true(camel > no_camel)
        end)

        it("awards consecutive run bonus", function()
            local consecutive = score("abcdef", "abc")
            local scattered = score("axbxcdef", "abc")
            assert.is_not_nil(consecutive)
            assert.is_not_nil(scattered)
            assert.is_true(consecutive > scattered)
        end)

        it("is case insensitive", function()
            local result = score("ABC", "abc")
            assert.is_not_nil(result)
        end)

        it("handles single character pattern", function()
            local result = score("hello", "h")
            assert.is_not_nil(result)
        end)

        it("handles pattern same length as string", function()
            local result = score("abc", "abc")
            assert.is_not_nil(result)
        end)

        it("scores start-of-string match higher", function()
            local at_start = score("abc", "a")
            local at_middle = score("xxa", "a")
            assert.is_not_nil(at_start)
            assert.is_not_nil(at_middle)
            assert.is_true(at_start > at_middle)
        end)
    end)

    describe("lua sorter", function()
        local sort = fuzzy.sorters.lua

        it("matches exact strings", function()
            local items = { "apple", "banana", "cherry" }
            local res = sort(items, "apple")
            assert.are.same({ "apple" }, res)
        end)

        it("matches partial strings", function()
            local items = { "apple", "apricot", "banana" }
            local res = sort(items, "ap")

            assert.are.same("apple", res[1])
            assert.are.same("apricot", res[2])
            assert.are.same(2, #res)
        end)

        it("handles fuzzy matches", function()
            local items = { "foobar", "fbr", "baz" }
            local res = sort(items, "fbr")
            assert.are.same({ "fbr", "foobar" }, res)
        end)

        it("returns empty list for no matches", function()
            local items = { "a", "b" }
            local res = sort(items, "z")
            assert.are.same({}, res)
        end)

        it("is case insensitive", function()
            local items = { "Apple" }
            local res = sort(items, "app")
            assert.are.same({ "Apple" }, res)
        end)

        it("handles multiple tokens (AND logic)", function()
            local items = { "hello world", "hello there", "world map" }
            local res = sort(items, "hello world")
            assert.are.same({ "hello world" }, res)

            local res2 = sort(items, "world hello")
            assert.are.same({ "hello world" }, res2)
        end)

        it("returns all items for empty query", function()
            local items = { "a", "b", "c" }
            local res = sort(items, "")
            assert.are.same({ "a", "b", "c" }, res)
        end)

        it("returns all items for whitespace-only query", function()
            local items = { "a", "b", "c" }
            local res = sort(items, "   ")
            assert.are.same({ "a", "b", "c" }, res)
        end)

        it("ranks exact prefix match above mid-string match", function()
            local items = { "xyzapple", "applexyz" }
            local res = sort(items, "apple")
            assert.are.same(2, #res)
            assert.are.same("applexyz", res[1])
        end)
    end)

    describe("native sorter", function()
        local native = fuzzy.sorters.native

        it("filters items correctly", function()
            local items = { "apple", "banana", "apricot" }
            local res = native(items, "ap")
            assert.is_true(#res >= 2)
            assert.is_true(vim.tbl_contains(res, "apple"))
            assert.is_true(vim.tbl_contains(res, "apricot"))
        end)

        it("returns empty for no matches", function()
            local items = { "apple", "banana" }
            local res = native(items, "zzz")
            assert.are.same({}, res)
        end)
    end)

    describe("filter", function()
        it("uses lua sorter fallback when blink is missing", function()
            local items = { "one", "two" }
            local res = fuzzy.filter(items, "one", { use_blink = true })

            assert.are.same(1, #res)
            assert.are.same("one", res[1].text)
        end)

        it("handles provider functions", function()
            local provider = function(q)
                return { "mock_" .. q }
            end
            local res = fuzzy.filter(provider, "test")
            assert.are.same(1, #res)
            assert.are.same("mock_test", res[1].text)
        end)

        it("returns all items for empty query", function()
            local items = { "a", "b", "c" }
            local res = fuzzy.filter(items, "")
            assert.are.same(3, #res)
            assert.are.same("a", res[1].text)
            assert.are.same("b", res[2].text)
            assert.are.same("c", res[3].text)
        end)

        it("resolves sorter by name string", function()
            local items = { "apple", "banana", "apricot" }
            local res = fuzzy.filter(items, "ap", { sorter = "lua" })
            assert.are.same(2, #res)
        end)

        -- ReferItem contract tests
        it("returns ReferItem[] when given string[] input", function()
            local items = { "foo", "bar" }
            local res = fuzzy.filter(items, "fo", { sorter = "lua" })
            assert.are.same(1, #res)
            assert.are.same("table", type(res[1]))
            assert.are.same("foo", res[1].text)
        end)

        it("returns ReferItem[] when given ReferItem[] input", function()
            local items = { { text = "foo" }, { text = "bar" } }
            local res = fuzzy.filter(items, "fo", { sorter = "lua" })
            assert.are.same(1, #res)
            assert.are.same("table", type(res[1]))
            assert.are.same("foo", res[1].text)
        end)

        it("preserves item.data through filter", function()
            local items = { { text = "foo", data = { lnum = 42 } }, { text = "bar" } }
            local res = fuzzy.filter(items, "fo", { sorter = "lua" })
            assert.are.same(1, #res)
            assert.are.same("foo", res[1].text)
            assert.are.same(42, res[1].data.lnum)
        end)

        it("returns all ReferItems for empty query", function()
            local items = { { text = "foo" }, { text = "bar" } }
            local res = fuzzy.filter(items, "", {})
            assert.are.same(2, #res)
            assert.are.same("foo", res[1].text)
            assert.are.same("bar", res[2].text)
        end)
    end)

    describe("register_items", function()
        it("extracts .text for blink registration from ReferItem inputs", function()
            -- When blink is not available, register_items returns false — just verify
            -- the function handles ReferItem tables without error
            local items = { { text = "alpha" }, { text = "beta" } }
            -- blink is stubbed as unavailable, so this returns false without error
            local ok = fuzzy.register_items(items)
            assert.is_false(ok)
        end)
    end)
end)
