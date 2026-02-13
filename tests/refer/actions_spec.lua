local refer = require "refer"
local Picker = require "refer.picker"
local stub = require "luassert.stub"

local util = require "refer.util"

describe("refer.actions", function()
    local picker

    before_each(function()
        picker = refer.pick({}, function() end)
    end)

    after_each(function()
        if picker then
            picker:close()
        end
    end)

    it("toggle_mark marks the current item and advances", function()
        picker.current_matches = { "item1", "item2" }
        picker.selected_index = 1

        picker.actions.toggle_mark()

        assert.is_true(picker.marked["item1"])
        assert.are.same(2, picker.selected_index)

        picker.selected_index = 1
        picker.actions.toggle_mark()
        assert.is_false(picker.marked["item1"])
    end)

    describe("send_to_qf", function()
        before_each(function()
            stub(vim.fn, "setqflist")
            stub(vim.cmd, "copen")
        end)

        after_each(function()
            vim.fn.setqflist:revert()
            vim.cmd.copen:revert()
        end)

        it("sends marked items to quickfix", function()
            picker.marked = { ["file1:1:1"] = true, ["file2:2:2"] = true }
            picker.current_matches = { "file1:1:1", "file2:2:2", "file3:3:3" }

            picker.actions.send_to_qf()

            assert.stub(vim.fn.setqflist).was_called()
            local call = vim.fn.setqflist.calls[1]
            local what = call.refs[3]

            assert.are.same("Refer Selection", what.title)
            assert.are.same(2, #what.items)
        end)

        it("sends current selection if nothing marked", function()
            picker.marked = {}
            picker.current_matches = { "file1" }
            picker.selected_index = 1

            picker.actions.send_to_qf()

            local call = vim.fn.setqflist.calls[1]
            local what = call.refs[3]
            assert.are.same(1, #what.items)
            assert.are.same("file1", what.items[1].text)
        end)
        it("sends parsed items correctly (LSP format)", function()
            picker.marked = {}
            picker.current_matches = { "src/main.lua:10:5: content" }
            picker.selected_index = 1
            picker.parser = util.parsers.lsp

            picker.actions.send_to_qf()

            local call = vim.fn.setqflist.calls[1]
            local what = call.refs[3]
            local item = what.items[1]

            assert.are.same("src/main.lua", item.filename)
            assert.are.same(10, item.lnum)
            assert.are.same(5, item.col)
            assert.are.same(" content", item.text)
        end)

        it("sends parsed items correctly (grep format no space)", function()
            picker.marked = {}
            picker.current_matches = { "src/main.lua:10:5:content" }
            picker.selected_index = 1
            picker.parser = util.parsers.grep

            picker.actions.send_to_qf()

            local call = vim.fn.setqflist.calls[1]
            local what = call.refs[3]
            local item = what.items[1]

            assert.are.same("src/main.lua", item.filename)
            assert.are.same(10, item.lnum)
            assert.are.same(5, item.col)
            assert.are.same("content", item.text)
        end)

        it("sends parsed items correctly (LSP format no space)", function()
            picker.marked = {}
            picker.current_matches = { "src/main.lua:10:5:content" }
            picker.selected_index = 1
            picker.parser = util.parsers.lsp

            picker.actions.send_to_qf()

            local call = vim.fn.setqflist.calls[1]
            local what = call.refs[3]
            local item = what.items[1]

            assert.are.same("src/main.lua", item.filename)
            assert.are.same(10, item.lnum)
            assert.are.same(5, item.col)
            assert.are.same("content", item.text)
        end)
    end)

    describe("select_input", function()
        it("calls on_select with raw input", function()
            local selected
            picker.on_select = function(sel)
                selected = sel
            end

            vim.api.nvim_buf_set_lines(picker.input_buf, 0, -1, false, { "custom input" })

            picker.actions.select_input()

            assert.are.same("custom input", selected)
        end)
    end)
end)
