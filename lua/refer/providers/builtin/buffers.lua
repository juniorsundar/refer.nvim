local refer = require "refer"
local util = require "refer.util"

---Open buffer picker
---Shows all listed buffers with bufnr, path, and cursor position
---Keymap <C-x> closes the selected buffer
local function buffers(opts)
    local bufs = vim.api.nvim_list_bufs()
    local items = {}

    for _, bufnr in ipairs(bufs) do
        if vim.bo[bufnr].buflisted then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name ~= "" then
                local relative_path = util.get_relative_path(name)
                local row_col = vim.api.nvim_buf_get_mark(bufnr, '"')
                if row_col[1] == 0 then
                    row_col[1] = 1
                end
                if row_col[2] == 0 then
                    row_col[2] = 1
                end
                local entry = string.format("%d: %s:%d:%d", bufnr, relative_path, row_col[1], row_col[2])
                table.insert(items, {
                    text = entry,
                    data = {
                        bufnr = bufnr,
                        filename = name,
                        lnum = row_col[1],
                        col = row_col[2],
                    },
                })
            end
        end
    end

    return refer.pick(
        items,
        util.jump_to_location,
        vim.tbl_deep_extend("force", {
            prompt = "Buffers > ",
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "select_entry",
                ["<C-x>"] = function(refer_item, builtin)
                    -- refer_item is now a ReferItem table; extract data directly
                    local data = (type(refer_item) == "table" and refer_item.data)
                        or (util.parsers.buffer(type(refer_item) == "table" and refer_item.text or refer_item))
                    if data and data.bufnr then
                        local win = builtin.parameters.original_win
                        if win and vim.api.nvim_win_is_valid(win) then
                            local current_view_buf = vim.api.nvim_win_get_buf(win)
                            if current_view_buf == data.bufnr then
                                local scratch = vim.api.nvim_create_buf(false, true)
                                vim.bo[scratch].bufhidden = "wipe"
                                vim.api.nvim_win_set_buf(win, scratch)
                            end
                        end

                        pcall(vim.api.nvim_buf_delete, data.bufnr, { force = true })

                        local target_text = type(refer_item) == "table" and refer_item.text or refer_item
                        for i, item in ipairs(items) do
                            local item_text = type(item) == "table" and item.text or item
                            if item_text == target_text then
                                table.remove(items, i)
                                break
                            end
                        end

                        builtin.actions.refresh()
                    end
                end,
            },
            parser = util.parsers.buffer,
        }, opts or {})
    )
end

return buffers
