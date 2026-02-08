if vim.g.loaded_refer == 1 then
    return
end
vim.g.loaded_refer = 1

local subcommands = {
    Files = function()
        require("refer.providers.files").files()
    end,
    Grep = function()
        require("refer.providers.files").live_grep()
    end,
    Buffers = function()
        require("refer.providers.builtin").buffers()
    end,
    OldFiles = function()
        require("refer.providers.builtin").old_files()
    end,
    Commands = function()
        require("refer.providers.builtin").commands()
    end,
    References = function()
        require("refer.providers.lsp").references()
    end,
    Definitions = function()
        require("refer.providers.lsp").definitions()
    end,
}

vim.api.nvim_create_user_command("Refer", function(opts)
    local subcommand_key = opts.fargs[1]
    local func = subcommands[subcommand_key]
    if func then
        func()
    else
        vim.notify("Refer: Unknown subcommand: " .. subcommand_key, vim.log.levels.ERROR)
    end
end, {
    nargs = 1,
    complete = function(ArgLead, CmdLine, CursorPos)
        local keys = vim.tbl_keys(subcommands)
        table.sort(keys)
        return vim.tbl_filter(function(key)
            return key:find(ArgLead, 1, true) == 1
        end, keys)
    end,
})
