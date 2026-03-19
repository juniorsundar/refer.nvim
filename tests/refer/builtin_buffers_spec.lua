local refer = require "refer"
local builtin = require "refer.providers.builtin"
local util = require "refer.util"

describe("builtin.buffers", function()
    local picker
    local tmpdir = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
        vim.fn.delete(tmpdir, "rf")
    end)

    it("lists currently listed buffers", function()
        local file1 = tmpdir .. "/file1.lua"
        local file2 = tmpdir .. "/file2.lua"
        local f1 = io.open(file1, "w")
        f1:write "content1\n"
        f1:close()
        local f2 = io.open(file2, "w")
        f2:write "content2\n"
        f2:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file1))
        vim.cmd("edit " .. vim.fn.fnameescape(file2))

        picker = builtin.buffers()

        local found_file1 = false
        local found_file2 = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("file1.lua", 1, true) then
                found_file1 = true
            end
            if text:find("file2.lua", 1, true) then
                found_file2 = true
            end
        end

        assert.is_true(found_file1)
        assert.is_true(found_file2)
    end)

    it("formats entries as bufnr: path:lnum:col", function()
        local file = tmpdir .. "/formatted.lua"
        local f = io.open(file, "w")
        f:write "line\n"
        f:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file))

        picker = builtin.buffers()

        local found = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("formatted.lua", 1, true) then
                assert.is_truthy(text:match "^%d+: .+:%d+:%d+$")
                found = true
                break
            end
        end
        assert.is_true(found)
    end)

    it("skips unlisted buffers", function()
        local file = tmpdir .. "/unlisted.lua"
        local f = io.open(file, "w")
        f:write "content\n"
        f:close()

        vim.cmd("edit " .. vim.fn.fnameescape(file))
        local bufnr = vim.fn.bufnr(file)
        vim.bo[bufnr].buflisted = false

        picker = builtin.buffers()

        local found = false
        for _, item in ipairs(picker.items_or_provider) do
            local text = type(item) == "table" and item.text or item
            if text:find("unlisted.lua", 1, true) then
                found = true
                break
            end
        end
        assert.is_false(found)
    end)
end)

describe("builtin.old_files", function()
    local picker
    local tmpdir = vim.fn.tempname()

    before_each(function()
        vim.fn.mkdir(tmpdir, "p")
    end)

    after_each(function()
        if picker then
            picker:close()
            picker = nil
        end
        vim.fn.delete(tmpdir, "rf")
    end)

    it("lists readable files from v:oldfiles", function()
        local file = tmpdir .. "/old.lua"
        local f = io.open(file, "w")
        f:write "old content\n"
        f:close()

        vim.v.oldfiles = { file }

        picker = builtin.old_files()

        assert.is_true(#picker.items_or_provider >= 1)
        local first_text = type(picker.items_or_provider[1]) == "table" and picker.items_or_provider[1].text or picker.items_or_provider[1]
        assert.are.same(file, first_text)
    end)

    it("skips non-readable files", function()
        vim.v.oldfiles = { tmpdir .. "/nonexistent.lua" }

        picker = builtin.old_files()

        assert.are.same(0, #picker.items_or_provider)
    end)

    it("opens picker with correct prompt", function()
        vim.v.oldfiles = {}

        picker = builtin.old_files()

        assert.are.same("Recent Files > ", picker.opts.prompt)
    end)
end)
