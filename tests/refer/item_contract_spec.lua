local util = require "refer.util"

describe("refer.util.normalize_items", function()
    it("wraps bare strings into { text, data=nil } tables", function()
        local result = util.normalize_items { "foo", "bar" }
        assert.are.same({ { text = "foo" }, { text = "bar" } }, result)
    end)

    it("passes through already-structured items unchanged", function()
        local items = { { text = "foo", data = 42 }, { text = "bar" } }
        local result = util.normalize_items(items)
        assert.are.same({ { text = "foo", data = 42 }, { text = "bar" } }, result)
    end)

    it("returns empty table for empty input", function()
        assert.are.same({}, util.normalize_items {})
    end)

    it("handles mixed input: string and structured item", function()
        local items = { "hello", { text = "world", data = { lnum = 1 } } }
        local result = util.normalize_items(items)
        assert.are.same({
            { text = "hello" },
            { text = "world", data = { lnum = 1 } },
        }, result)
    end)

    it("does not re-wrap a structured item with data=nil (idempotent)", function()
        local item = { text = "only-text" }
        local result = util.normalize_items { item }

        assert.are.equal(1, #result)
        assert.are.same({ text = "only-text" }, result[1])

        assert.is_nil(result[1].text.text)
    end)
end)
