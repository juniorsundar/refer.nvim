local util = require "refer.util"
local stub = require "luassert.stub"

describe("refer.util", function()
    describe("parse_selection", function()
        it("parses buffer format", function()
            local input = "1: src/main.lua:10:5"
            local expected = {
                bufnr = 1,
                filename = "src/main.lua",
                lnum = 10,
                col = 5,
            }
            assert.are.same(expected, util.parse_selection(input, "buffer"))
        end)

        it("parses grep format", function()
            local input = "src/main.lua:10:5:local x = 1"
            local expected = {
                filename = "src/main.lua",
                lnum = 10,
                col = 5,
                content = "local x = 1",
            }
            assert.are.same(expected, util.parse_selection(input, "grep"))
        end)

        it("parses lsp format", function()
            local input = "src/main.lua:10:5"
            local expected = {
                filename = "src/main.lua",
                lnum = 10,
                col = 5,
            }
            assert.are.same(expected, util.parse_selection(input, "lsp"))
        end)

        it("parses simple file format", function()
            local input = "src/main.lua"
            local expected = {
                filename = "src/main.lua",
                lnum = 1,
                col = 1,
            }
            assert.are.same(expected, util.parse_selection(input, "file"))
        end)

        it("returns nil for invalid format", function()
            assert.is_nil(util.parse_selection("invalid", "buffer"))
        end)
    end)

    describe("complete_line", function()
        it("completes simple prefix", function()
            assert.are.same("test", util.complete_line("te", "test"))
        end)

        it("replaces after separator", function()
            assert.are.same("path/to/file", util.complete_line("path/to/fi", "file"))
        end)

        it("handles spaces as separators", function()
            assert.are.same("command argument", util.complete_line("command arg", "argument"))
        end)
    end)

    describe("get_relative_path", function()
        local original_cwd
        before_each(function()
            original_cwd = vim.fn.getcwd()
            stub(vim.fn, "getcwd", "/home/user/project")
        end)

        after_each(function()
            vim.fn.getcwd:revert()
        end)

        it("strips cwd from path", function()
            local abs = "/home/user/project/src/main.lua"
            assert.are.same("src/main.lua", util.get_relative_path(abs))
        end)

        it("leaves outside paths alone", function()
            local abs = "/etc/hosts"
            assert.are.same("/etc/hosts", util.get_relative_path(abs))
        end)
    end)
end)
