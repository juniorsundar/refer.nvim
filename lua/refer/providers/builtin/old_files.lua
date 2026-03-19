local refer = require "refer"
local util = require "refer.util"

---Open recent files picker
---Shows files from v:oldfiles that are still readable
local function old_files(opts)
    local results = {}

    for _, file in ipairs(vim.v.oldfiles) do
        if vim.fn.filereadable(file) == 1 then
            table.insert(results, { text = file, data = { filename = file } })
        end
    end

    return refer.pick(
        results,
        nil,
        vim.tbl_deep_extend("force", {
            prompt = "Recent Files > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
            },
            parser = util.parsers.file,
            on_select = function(selection, data)
                util.jump_to_location(selection, data)
                pcall(vim.cmd, 'normal! g`"')
            end,
        }, opts or {})
    )
end

return old_files
