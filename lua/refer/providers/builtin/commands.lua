local refer = require "refer"

local function is_bare_address(input)
    return input:match "^%d+$" or input == "%" or input == "." or input == "$"
end

local function complete_cmdline(input)
    if input == "" then
        return vim.fn.getcompletion("", "command")
    end

    local matches = vim.fn.getcompletion(input, "cmdline")
    if #matches == 0 and is_bare_address(input) then
        return { input }
    end

    local prefix = input:match "^'[<a-z],'[>a-z]" or input:match "^%d+,%d+"
    if prefix then
        local remainder = input:sub(#prefix + 1)
        if not remainder:match "[%s%.%/:\\\\]" then
            local new_matches = {}
            for _, m in ipairs(matches) do
                if not vim.startswith(m, prefix) then
                    table.insert(new_matches, prefix .. m)
                else
                    table.insert(new_matches, m)
                end
            end
            return new_matches
        end
    end

    return matches
end

---Open command picker (like M-x in Emacs)
---Shows all available vim commands with completion
local function commands(opts)
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

    local default_text = nil
    if (opts and opts.range == 2) or vim.fn.mode():find "^[vV\22]" then
        default_text = "'<,'>"
    end

    local preview_applied = false
    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_win_get_buf(original_win)

    local function cleanup_preview()
        if preview_applied then
            vim.api.nvim_buf_call(original_buf, function()
                pcall(vim.cmd, "silent! undo")
            end)
            preview_applied = false
        end
    end

    local function do_sub_preview(input)
        cleanup_preview()

        -- Strip optional *do prefix (cdo, cfdo, argdo, bufdo, windo, tabdo)
        -- before matching the substitute pattern, so preview works for both
        -- plain substitutes and do-command substitutes.
        local do_cmd, do_rest = input:match "^([a-z]*do)%s+(.*)$"
        local stripped = do_rest or input

        local range, sep = stripped:match "^([%%'%d,$.<>]*)s(.)"
        if not sep or sep:match "[%w%s]" then
            return
        end

        -- When a *do prefix was present, apply the substitute across the whole
        -- buffer for preview (the real do-loop runs per-line on confirm).
        if do_cmd then
            if range == "" or range == nil then
                stripped = "%" .. stripped
            end
        end
        input = stripped

        local unescaped_count = 0
        local i = 1
        while i <= #input do
            local c = input:sub(i, i)
            if c == "\\" then
                i = i + 2
            elseif c == sep then
                unescaped_count = unescaped_count + 1
                i = i + 1
            else
                i = i + 1
            end
        end

        local preview_input = input
        if unescaped_count >= 3 then
            local esc_sep = sep:gsub("%W", "%%%1")
            local match_flags = input:match(esc_sep .. "([&cegiInp#lr]*)$")
            if match_flags and match_flags:match "c" then
                local new_flags = match_flags:gsub("c", "")
                preview_input = input:sub(1, -(#match_flags + 1)) .. new_flags
            end
        end

        vim.api.nvim_buf_call(original_buf, function()
            vim.cmd "let &ul=&ul"
            local ok = pcall(vim.cmd, "noautocmd keepjumps " .. preview_input)
            if ok then
                preview_applied = true
            end
        end)
    end

    return refer.pick(
        function(input)
            return complete_cmdline(input)
        end,
        function(input_text)
            cleanup_preview()
            vim.fn.histadd("cmd", input_text)
            local ok, result = pcall(vim.api.nvim_exec2, input_text, { output = true })
            if not ok then
                vim.notify(tostring(result), vim.log.levels.ERROR)
            elseif result and result.output and vim.trim(result.output) ~= "" then
                vim.notify(vim.trim(result.output), vim.log.levels.INFO)
            end
        end,
        vim.tbl_deep_extend("force", {
            prompt = "M-x > ",
            default_text = default_text,
            keymaps = {
                ["<C-p>"] = function(_, builtin)
                    cycle_history(builtin, 1)
                end,
                ["<C-n>"] = function(_, builtin)
                    cycle_history(builtin, -1)
                end,
            },
            on_change = function(input, update_ui_callback)
                do_sub_preview(input)

                update_ui_callback(complete_cmdline(input))
            end,
            on_close = function()
                cleanup_preview()
                if opts and opts.on_close then
                    opts.on_close()
                end
            end,
        }, opts or {})
    )
end

return commands
