local Picker = require "refer.picker"

---@class ReferModule
local M = {}

---@type table Default options set via setup()
local default_opts = {}

---Configure default options for all pickers
---@param opts ReferOptions|nil Configuration options
function M.setup(opts)
    default_opts = opts or {}
end

---Open a picker with items or a provider function
---@param items_or_provider table|fun(query: string): table List of strings or a function that returns items based on query
---@param on_select fun(selection: string, data: SelectionData|nil)|nil Callback when item is selected
---@param opts ReferOptions|nil Options to override defaults
---@return Picker picker The picker instance
function M.pick(items_or_provider, on_select, opts)
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})
    if on_select then
        opts.on_select = on_select
    end

    local picker = Picker.new(items_or_provider, opts)
    picker:show()
    return picker
end

return M
