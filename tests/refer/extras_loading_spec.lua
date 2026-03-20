local refer = require "refer"

describe("refer extras loading", function()
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
        package.loaded["refer.extras.find_file"] = nil
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
        package.loaded["refer.extras.find_file"] = nil
        package.loaded["refer.commands"] = nil
        refer = require "refer"
    end)

    it("treats disabled extras like unknown commands", function()
        local notifications = {}
        vim.notify = function(message, level)
            table.insert(notifications, { message = message, level = level })
        end

        load_plugin_commands()
        vim.api.nvim_cmd({ cmd = "Refer", args = { "Extras", "FindFile" } }, {})

        assert.are.same(1, #notifications)
        assert.are.same("Refer: Unknown subcommand: Extras", notifications[1].message)
        assert.are.same(vim.log.levels.ERROR, notifications[1].level)
        assert.is_nil(package.loaded["refer.extras.find_file"])
    end)

    it("lazy-loads the enabled extra only when executed", function()
        local calls = {}
        package.preload["refer.extras.find_file"] = function()
            return {
                run = function(opts)
                    table.insert(calls, opts)
                end,
            }
        end

        load_plugin_commands()
        refer.setup { extras = { find_file = true } }
        local commands = refer.get_commands()

        assert.is_nil(package.loaded["refer.extras.find_file"])
        assert.is_function(commands.Extras.FindFile)

        vim.api.nvim_cmd({ cmd = "Refer", args = { "Extras", "FindFile" } }, {})

        assert.are.same(1, #calls)
        assert.is_table(calls[1])
        assert.is_truthy(package.loaded["refer.extras.find_file"])
        package.preload["refer.extras.find_file"] = nil
    end)
end)
