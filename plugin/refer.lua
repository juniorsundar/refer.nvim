if vim.g.loaded_refer == 1 then
    return
end
vim.g.loaded_refer = 1

local subcommands = {
    Files = function(opts)
        require("refer.providers.files").files(opts)
    end,
    Grep = function(opts)
        require("refer.providers.files").live_grep(opts)
    end,
    Buffers = function(opts)
        require("refer.providers.builtin").buffers(opts)
    end,
    OldFiles = function(opts)
        require("refer.providers.builtin").old_files(opts)
    end,
    Commands = function(opts)
        require("refer.providers.builtin").commands(opts)
    end,
    References = function(opts)
        require("refer.providers.lsp").references(opts)
    end,
    Definitions = function(opts)
        require("refer.providers.lsp").definitions(opts)
    end,
}

vim.api.nvim_create_user_command("Refer", function(opts)
    local subcommand_key = opts.fargs[1]
    local func = subcommands[subcommand_key]
    if func then
        func(opts)
    else
        vim.notify("Refer: Unknown subcommand: " .. subcommand_key, vim.log.levels.ERROR)
    end
end, {
    nargs = 1,
    range = true,
    complete = function(ArgLead, CmdLine, CursorPos)
        local keys = vim.tbl_keys(subcommands)
        table.sort(keys)
        return vim.tbl_filter(function(key)
            return key:find(ArgLead, 1, true) == 1
        end, keys)
    end,
})
