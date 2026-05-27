local refer = require "refer"

-- ACKNOWLEDGMENT: This is heavily inspired by https://github.com/johnpgr/dotfiles/blob/ae2955439a43e4ed25859ca7c4da137e8e91a5a7/nvim/lua/plugins/refer.lua#L959-L1043

---Collect tag files for the configured help languages.
---@return string[] langs Ordered list of languages to search.
---@return table<string, string[]> tag_files Map of language to its tag files.
local function collect_tag_files()
    local langs = vim.split(vim.o.helplang, ",", { trimempty = true })
    if not vim.tbl_contains(langs, "en") then
        table.insert(langs, "en")
    end

    local langs_map = {}
    for _, lang in ipairs(langs) do
        langs_map[lang] = true
    end

    local tag_files = {}
    local function add_tag_file(lang, file)
        if not langs_map[lang] then
            return
        end
        if not tag_files[lang] then
            tag_files[lang] = {}
        end
        table.insert(tag_files[lang], file)
    end

    local rtp = vim.o.runtimepath
    local lazy = package.loaded["lazy.core.util"]
    if lazy and lazy.get_unloaded_rtp then
        local paths = lazy.get_unloaded_rtp ""
        if #paths > 0 then
            rtp = rtp .. "," .. table.concat(paths, ",")
        end
    end

    local all_files = vim.fn.globpath(rtp, "doc/*", true, true)
    for _, fullpath in ipairs(all_files) do
        local file = vim.fs.basename(fullpath)
        if file == "tags" then
            add_tag_file("en", fullpath)
        elseif file:match "^tags%-..$" then
            add_tag_file(file:sub(-2), fullpath)
        end
    end

    return langs, tag_files
end

---Build the list of tags and a lookup table from tag name to language-qualified key.
---@return string[] tags
---@return table<string, string> lookup
local function build_tags()
    local langs, tag_files = collect_tag_files()

    local tags = {}
    local lookup = {}
    local seen = {}

    for _, lang in ipairs(langs) do
        for _, file in ipairs(tag_files[lang] or {}) do
            for _, line in ipairs(vim.fn.readfile(file)) do
                if not line:match "^!_TAG_" then
                    local fields = vim.split(line, "\t", { trimempty = true })
                    if #fields == 3 and not seen[fields[1]] then
                        if fields[1] ~= "help-tags" or fields[2] ~= "tags" then
                            table.insert(tags, fields[1])
                            lookup[fields[1]] = fields[1] .. "@" .. lang
                            seen[fields[1]] = true
                        end
                    end
                end
            end
        end
    end

    return tags, lookup
end

---Open help tags picker
---Searches Vim help tags across the runtime path (respecting 'helplang')
---and opens :help for the selected entry.
local function help_tags(opts)
    local tags, lookup = build_tags()

    if #tags == 0 then
        vim.notify("Refer: no help tags found", vim.log.levels.WARN)
        return
    end

    return refer.pick(
        tags,
        function(selection)
            if not selection or selection == "" then
                return
            end

            local value = lookup[selection] or selection
            vim.cmd("help " .. vim.fn.fnameescape(value))
        end,
        vim.tbl_deep_extend("force", {
            prompt = "Help > ",
            frecency = { provider = "help_tags", key_strategy = "text" },
            keymaps = {
                ["<CR>"] = "select_entry",
            },
        }, opts or {})
    )
end

return help_tags
