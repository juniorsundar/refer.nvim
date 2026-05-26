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
            frecency = { provider = "buffers", key_strategy = "filepath" },
            keymaps = {
                ["<Tab>"] = "toggle_mark",
                ["<CR>"] = "open_marked",
                ["<C-x>"] = function(refer_item, builtin)
                    local targets = {}
                    for _, item in ipairs(items) do
                        local key = type(item) == "table" and item.text or item
                        if builtin.marked[key] then
                            table.insert(targets, item)
                        end
                    end

                    if #targets == 0 then
                        local target_text = type(refer_item) == "table" and refer_item.text or refer_item
                        local data = (type(refer_item) == "table" and refer_item.data)
                            or (util.parsers.buffer(target_text))
                        if not (data and data.bufnr) then
                            return
                        end

                        targets = { refer_item }
                    end

                    local target_keys = {}
                    local target_bufnrs = {}
                    for _, item in ipairs(targets) do
                        local text = type(item) == "table" and item.text or item
                        local data = (type(item) == "table" and item.data) or util.parsers.buffer(text)
                        if data and data.bufnr then
                            target_keys[text] = true
                            table.insert(target_bufnrs, data.bufnr)
                        end
                    end

                    if #target_bufnrs == 0 then
                        return
                    end

                    local preview_was_enabled = builtin.picker.preview_enabled
                    builtin.picker.preview_enabled = false

                    local win = builtin.parameters.original_win
                    if win and vim.api.nvim_win_is_valid(win) then
                        local current_view_buf = vim.api.nvim_win_get_buf(win)
                        for _, bufnr in ipairs(target_bufnrs) do
                            if current_view_buf == bufnr then
                                local scratch = vim.api.nvim_create_buf(false, true)
                                vim.bo[scratch].bufhidden = "wipe"
                                vim.api.nvim_win_set_buf(win, scratch)
                                break
                            end
                        end
                    end

                    for i = #items, 1, -1 do
                        local item_text = type(items[i]) == "table" and items[i].text or items[i]
                        if target_keys[item_text] then
                            table.remove(items, i)
                        end
                    end

                    builtin.picker:set_items(items)

                    for key in pairs(target_keys) do
                        builtin.marked[key] = nil
                    end

                    for _, bufnr in ipairs(target_bufnrs) do
                        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
                    end

                    builtin.picker.preview_enabled = preview_was_enabled
                end,
            },
            parser = util.parsers.buffer,
        }, opts or {})
    )
end

return buffers
