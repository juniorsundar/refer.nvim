local refer = require "refer"

describe("refer extras registry", function()
    local original_loaded_refer
    local original_registry
    local original_notify

    local function load_plugin_commands()
        pcall(vim.api.nvim_del_user_command, "Refer")
        refer._registry = {}
        vim.g.loaded_refer = nil
        package.loaded["refer.commands"] = nil
        dofile(vim.fn.getcwd() .. "/plugin/refer.lua")
        return refer.get_commands()
    end

    local function reset_setup_state()
        package.loaded["refer"] = nil
        package.loaded["refer.extras"] = nil
        refer = require "refer"
    end

    before_each(function()
        original_loaded_refer = vim.g.loaded_refer
        original_registry = vim.deepcopy(refer.get_commands())
        original_notify = vim.notify
        reset_setup_state()
    end)

    after_each(function()
        pcall(vim.api.nvim_del_user_command, "Refer")
        vim.g.loaded_refer = original_loaded_refer
        vim.notify = original_notify
        refer._registry = original_registry or {}
        package.loaded["refer"] = nil
        package.loaded["refer.extras"] = nil
        package.loaded["refer.commands"] = nil
        refer = require "refer"
    end)

    it("enables Extras FindFile only through setup", function()
        load_plugin_commands()
        refer.setup({ extras = { find_file = true } })
        local commands = refer.get_commands()

        assert.is_table(commands.Extras)
        assert.is_function(commands.Extras.FindFile)
        assert.is_nil(commands.FindFile)
        assert.is_nil(commands.ReferExtras)
    end)

    it("keeps default completion core-only", function()
        load_plugin_commands()

        local completions = require("refer.commands").complete("", "Refer ", #("Refer "))

        assert.is_false(vim.tbl_contains(completions, "Extras"))
        assert.is_true(vim.tbl_contains(completions, "Files"))
        assert.is_true(vim.tbl_contains(completions, "Grep"))
    end)

    it("completes the enabled extras namespace path", function()
        load_plugin_commands()
        refer.setup({ extras = { find_file = true } })

        local root = require("refer.commands").complete("", "Refer ", #("Refer "))
        local extras = require("refer.commands").complete("", "Refer Extras ", #("Refer Extras "))

        assert.is_true(vim.tbl_contains(root, "Extras"))
        assert.are.same({ "FindFile" }, extras)
    end)
end)
