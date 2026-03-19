local refer = require "refer"

local M = {}

local extras = {
    find_file = {
        path = { "Extras", "FindFile" },
        run = function(opts)
            local ok, extra = pcall(require, "refer.extras.find_file")
            if not ok then
                vim.notify("Refer: Extra not available: FindFile", vim.log.levels.ERROR)
                return
            end

            extra.run(opts)
        end,
    },
}

function M.setup(enabled)
    local commands = refer.get_commands()
    commands.Extras = nil

    enabled = enabled or {}

    for key, config in pairs(extras) do
        if enabled[key] then
            refer.add_command(config.path, config.run)
        end
    end
end

return M
