local builtin = require "refer.providers.builtin"
local stub = require "luassert.stub"

describe("builtin.commands execution", function()
    it("handles range correctly", function()
        local s = stub(vim, "cmd")
        local picker = builtin.commands { range = 2, line1 = 10, line2 = 20 }

        -- Check default text is set
        assert.equals("'<,'>", picker.opts.default_text)

        -- The provider logic now ensures the prefix is in the item.
        -- We simulate selecting an item that has the prefix.
        picker.on_select "'<,'>sort"

        assert.stub(s).was.called_with "'<,'>sort"
        s:revert()
    end)

    it("handles no range correctly", function()
        local s = stub(vim, "cmd")
        local picker = builtin.commands()

        assert.equals(nil, picker.opts.default_text)

        picker.on_select "echo 'hi'"

        assert.stub(s).was.called_with "echo 'hi'"
        s:revert()
    end)
end)
