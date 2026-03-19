local refer = require "refer"

---Open macro editor
---Shows all populated registers and allows live editing of their contents
local function macros(opts)
    local items = {}
    local registers = 'abcdefghijklmnopqrstuvwxyz0123456789"/-*+.'
    for i = 1, #registers do
        local reg = registers:sub(i, i)
        local val = vim.fn.getreg(reg)
        if val ~= "" then
            local readable_val = vim.fn.keytrans(val)
            table.insert(items, {
                text = string.format("%s: %s", reg, readable_val),
                data = { register = reg, content = readable_val },
            })
        end
    end

    local caller_win = vim.api.nvim_get_current_win()
    local caller_buf = vim.api.nvim_win_get_buf(caller_win)

    local function edit_macro(reg, initial_content, original_win, original_buf, parent_opts)
        local preview_applied = false
        local preview_view = nil
        local preview_fold = nil

        local function cleanup_preview()
            if preview_applied then
                vim.api.nvim_win_call(original_win, function()
                    pcall(vim.cmd, "silent! undo")
                    if preview_view then
                        vim.fn.winrestview(preview_view)
                        preview_view = nil
                    end
                end)
                if preview_fold then
                    vim.wo[original_win].foldmethod = preview_fold.foldmethod
                    vim.wo[original_win].foldexpr = preview_fold.foldexpr
                    vim.wo[original_win].foldenable = preview_fold.foldenable
                    vim.wo[original_win].foldlevel = preview_fold.foldlevel
                    vim.wo[original_win].foldcolumn = preview_fold.foldcolumn
                    preview_fold = nil
                end
                preview_applied = false
            end
        end

        local function do_macro_preview(input)
            cleanup_preview()
            if input == "" then
                return
            end

            vim.api.nvim_win_call(original_win, function()
                vim.cmd "let &ul=&ul"
                preview_fold = {
                    foldmethod = vim.wo[original_win].foldmethod,
                    foldexpr = vim.wo[original_win].foldexpr,
                    foldenable = vim.wo[original_win].foldenable,
                    foldlevel = vim.wo[original_win].foldlevel,
                    foldcolumn = vim.wo[original_win].foldcolumn,
                }
                vim.wo[original_win].foldmethod = "manual"
                vim.wo[original_win].foldexpr = ""
                vim.wo[original_win].foldenable = false
                preview_view = vim.fn.winsaveview()
                local termcodes = vim.api.nvim_replace_termcodes(input, true, true, true)
                local ok, err = pcall(vim.cmd, "noautocmd keepjumps normal! " .. termcodes)
                if ok then
                    preview_applied = true
                else
                    preview_view = nil
                    vim.notify("do_macro_preview failed: " .. tostring(err), vim.log.levels.WARN)
                end
            end)
        end

        local function save_macro(input_text)
            cleanup_preview()
            local termcodes = vim.api.nvim_replace_termcodes(input_text, true, true, true)
            vim.fn.setreg(reg, termcodes)
            vim.notify("Updated register '" .. reg .. "'")
        end

        refer.pick(
            {},
            save_macro,
            vim.tbl_deep_extend("force", {
                prompt = string.format("Edit Macro [%s] > ", reg),
                default_text = initial_content,
                preview = { enabled = false },
                keymaps = {
                    ["<CR>"] = "select_input",
                },
                on_change = function(input, update_ui_callback)
                    do_macro_preview(input)
                    update_ui_callback {}
                end,
                on_close = function()
                    cleanup_preview()
                end,
                on_confirm = save_macro,
            }, parent_opts or {})
        )

        do_macro_preview(initial_content)
    end

    local picker = refer.pick(
        items,
        function(selection, item_data)
            local reg = (item_data and item_data.register) or selection:sub(1, 1)
            local content = (item_data and item_data.content) or selection:sub(4)

            vim.schedule(function()
                edit_macro(reg, content, caller_win, caller_buf, opts)
            end)
        end,
        vim.tbl_deep_extend("force", {
            prompt = "Macros > ",
            preview = { enabled = false },
            keymaps = {
                ["<CR>"] = "select_entry",
                ["<C-r>"] = function(refer_item, builtin)
                    local selection = type(refer_item) == "table" and refer_item.text or refer_item
                    if not selection or selection == "" then
                        return
                    end
                    local reg = (type(refer_item) == "table" and refer_item.data and refer_item.data.register)
                        or selection:sub(1, 1)
                    vim.fn.setreg(reg, "")
                    builtin.actions.close()
                    vim.schedule(function()
                        edit_macro(reg, "", caller_win, caller_buf, opts)
                    end)
                end,
            },
        }, opts or {})
    )
    picker.items = items
    return picker
end

return macros
