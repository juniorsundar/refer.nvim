local fuzzy = require "refer.fuzzy"
local blink = require "refer.blink"
local stub = require "luassert.stub"

describe("refer.fuzzy", function()
    stub(blink, "is_available", false)

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
    end)

    describe("filter", function()
        it("uses lua sorter fallback when blink is missing", function()
            local items = { "one", "two" }
            local res = fuzzy.filter(items, "one", { use_blink = true })

            assert.are.same({ "one" }, res)
        end)

        it("handles provider functions", function()
            local provider = function(q)
                return { "mock_" .. q }
            end
            local res = fuzzy.filter(provider, "test")
            assert.are.same({ "mock_test" }, res)
        end)
    end)
end)
