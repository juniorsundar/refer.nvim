local builtin = require "refer.providers.builtin"
local refer = require "refer"
local stub = require "luassert.stub"

describe("builtin.commands completion", function()
    it("does NOT prepend range prefix when there's a space after it", function()
        local s_getcompletion = stub(vim.fn, "getcompletion")
        s_getcompletion.on_call_with("'<,'>Refer ", "cmdline").returns { "Files", "Selection" }

        local picker = builtin.commands { range = 2, line1 = 1, line2 = 10 }

        local s_pick = stub(refer, "pick")
        builtin.commands { range = 2, line1 = 1, line2 = 10 }

        local provider = s_pick.calls[1].refs[1]

        local matches = provider "'<,'>Refer "

        assert.are.same({ "Files", "Selection" }, matches)

        s_getcompletion:revert()
        s_pick:revert()
    end)

    it("DOES prepend range prefix when there's NO space after it", function()
        local s_getcompletion = stub(vim.fn, "getcompletion")
        s_getcompletion.on_call_with("'<,'>Ref", "cmdline").returns { "Refer" }

        local s_pick = stub(refer, "pick")
        builtin.commands { range = 2, line1 = 1, line2 = 10 }

        local provider = s_pick.calls[1].refs[1]

        local matches = provider "'<,'>Ref"

        assert.are.same({ "'<,'>Refer" }, matches)

        s_getcompletion:revert()
        s_pick:revert()
    end)

    it("keeps bare Ex addresses as executable candidates", function()
        local s_getcompletion = stub(vim.fn, "getcompletion")
        s_getcompletion.on_call_with("32", "cmdline").returns {}
        s_getcompletion.on_call_with("%", "cmdline").returns {}
        s_getcompletion.on_call_with(".", "cmdline").returns {}
        s_getcompletion.on_call_with("$", "cmdline").returns {}

        local s_pick = stub(refer, "pick")
        builtin.commands()

        local provider = s_pick.calls[1].refs[1]

        assert.are.same({ "32" }, provider "32")
        assert.are.same({ "%" }, provider "%")
        assert.are.same({ "." }, provider ".")
        assert.are.same({ "$" }, provider "$")

        s_getcompletion:revert()
        s_pick:revert()
    end)
end)
