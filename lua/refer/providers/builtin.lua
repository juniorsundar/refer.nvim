---@class BuiltinProvider
local M = {}

local refer = require "refer"
local util = require "refer.util"

---Open command picker (like M-x in Emacs)
---Shows all available vim commands with completion
function M.commands()
    local history_state = {
        index = 0,
        prefix = nil,
        last_tick = nil,
        matches = nil,
    }

    local function cycle_history(builtin, direction)
        local input_buf = builtin.picker.input_buf
        local current_tick = vim.api.nvim_buf_get_changedtick(input_buf)

        if history_state.last_tick and current_tick ~= history_state.last_tick then
            history_state.index = 0
            history_state.prefix = nil
            history_state.matches = nil
        end

        if not history_state.matches then
            local input = vim.api.nvim_get_current_line()
            history_state.prefix = input
            history_state.matches = {}
            local seen = {}
            local count = vim.fn.histnr "cmd"
            for i = count, 1, -1 do
                local entry = vim.fn.histget("cmd", i)
                if entry and entry ~= "" and not seen[entry] then
                    if not history_state.prefix or vim.startswith(entry, history_state.prefix) then
                        table.insert(history_state.matches, entry)
                        seen[entry] = true
                    end
                end
            end
        end

        local new_index = history_state.index + direction
        if new_index < 0 then
            new_index = 0
        elseif new_index > #history_state.matches then
            new_index = #history_state.matches
        end

        if new_index == history_state.index then
            return
        end

        local text_to_show
        if new_index == 0 then
            text_to_show = history_state.prefix
        else
            text_to_show = history_state.matches[new_index]
        end

        history_state.index = new_index
        builtin.picker.ui:update_input { text_to_show }

        history_state.last_tick = vim.api.nvim_buf_get_changedtick(input_buf)
    end

    return refer.pick(function(input)
        if input == "" then
            return vim.fn.getcompletion("", "command")
        end
        return vim.fn.getcompletion(input, "cmdline")
    end, function(input_text)
        vim.fn.histadd("cmd", input_text)
        vim.cmd(input_text)
    end, {
        prompt = "M-x > ",
        keymaps = {
            ["<C-p>"] = function(_, builtin)
                cycle_history(builtin, 1)
            end,
            ["<C-n>"] = function(_, builtin)
                cycle_history(builtin, -1)
            end,
        },
    })
end

---Open buffer picker
---Shows all listed buffers with bufnr, path, and cursor position
---Keymap <C-x> closes the selected buffer
function M.buffers()
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
                table.insert(items, entry)
            end
        end
    end

    return refer.pick(items, util.jump_to_location, {
        prompt = "Buffers > ",
        keymaps = {
            ["<Tab>"] = "toggle_mark",
            ["<CR>"] = "select_entry",
            ["<C-x>"] = function(selection, builtin)
                local parser = util.parsers.buffer
                local data = parser(selection)
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

                    for i, item in ipairs(items) do
                        if item == selection then
                            table.remove(items, i)
                            break
                        end
                    end

                    builtin.actions.refresh()
                end
            end,
        },
        parser = util.parsers.buffer,
    })
end

---Open recent files picker
---Shows files from v:oldfiles that are still readable
function M.old_files()
    local results = {}

    for _, file in ipairs(vim.v.oldfiles) do
        if vim.fn.filereadable(file) == 1 then
            table.insert(results, file)
        end
    end

    return refer.pick(results, nil, {
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
    })
end

return M
