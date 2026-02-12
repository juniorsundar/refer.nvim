local refer = require "refer"
local util = require "refer.util"

describe("refer (custom parsers)", function()
    it("can register and use a custom parser", function()
        -- Define a custom schema for "Line 10, Col 5 in file.txt"
        local schema = {
            pattern = "^Line (%d+), Col (%d+) in (.*)",
            keys = { "lnum", "col", "filename" },
            types = { lnum = tonumber, col = tonumber },
        }

        refer.setup {
            custom_parsers = {
                verbose_log = schema,
            },
        }

        local selection = "Line 42, Col 7 in src/main.lua"
        local parsed = util.parse_selection(selection, "verbose_log")

        assert.is_not_nil(parsed)
        assert.are.same("src/main.lua", parsed.filename)
        assert.are.same(42, parsed.lnum)
        assert.are.same(7, parsed.col)
    end)

    it("ignores invalid parser registration", function()
        util.register_parser("invalid_1", nil)

        local res = util.parse_selection("something", "invalid_1")
        assert.is_nil(res)
    end)

    it("handles multiple patterns in schema", function()
        local schema = {
            pattern = {
                "^(.*):(%d+)",
                "^(.*)%((%d+)%)",
            },
            keys = { "filename", "lnum" },
            types = { lnum = tonumber },
        }

        util.register_parser("multi_format", schema)

        local res1 = util.parse_selection("test.lua:10", "multi_format")
        assert.are.same(10, res1.lnum)
        assert.are.same("test.lua", res1.filename)

        local res2 = util.parse_selection("test.lua(20)", "multi_format")
        assert.are.same(20, res2.lnum)
        assert.are.same("test.lua", res2.filename)
    end)
end)
