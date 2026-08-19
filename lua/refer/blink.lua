---@class BlinkModule
local M = {}

local VERSION = "v1.10.2"
local BASE_URL = "https://github.com/Saghen/blink.cmp/releases/download"

---@type boolean Whether the Rust module has been loaded successfully
local has_loaded = false

---@type table|nil The loaded Rust module (from an installed+built blink.cmp)
local rust_module = nil

---@type boolean Whether the user has declined the download prompt
local declined_download = false

---@type boolean Whether a download is in progress
local is_downloading = false

---@type function|nil User-supplied prepare hook. Called when the blink native-module
-- load fails, before falling back to a download. A truthy return retries the
-- native-module load; a falsy return falls through to the download prompt.
local prepare_hook = nil

---Set the user-supplied prepare hook. Truthy retries the native-module load.
---@param hook function|nil The hook, or nil to clear it.
function M.set_prepare_hook(hook)
    prepare_hook = hook
end

---Get the library extension for the current OS
---@return string extension ".so", ".dylib", or ".dll"
local function get_lib_extension()
    if jit.os:lower() == "mac" or jit.os:lower() == "osx" then
        return ".dylib"
    elseif jit.os:lower() == "windows" then
        return ".dll"
    else
        return ".so"
    end
end

---Determine the system triple (e.g., x86_64-unknown-linux-gnu)
---@return string|nil triple System triple or nil if unsupported
local function get_system_triple()
    local os = jit.os:lower()
    local arch = jit.arch:lower()

    if os == "osx" or os == "mac" then
        if arch == "arm64" or arch == "aarch64" then
            return "aarch64-apple-darwin"
        end
        return "x86_64-apple-darwin"
    elseif os == "windows" then
        return "x86_64-pc-windows-msvc"
    elseif os == "linux" then
        local libc = "gnu"
        local f = io.open("/etc/alpine-release", "r")
        if f then
            libc = "musl"
            f:close()
        end

        if arch == "arm64" or arch == "aarch64" then
            return "aarch64-unknown-linux-" .. libc
        end
        return "x86_64-unknown-linux-" .. libc
    end
    return nil
end

---Get the local path for the fallback library
---@return string path Path to the library file
local function get_lib_path()
    local info = debug.getinfo(1, "S")
    local script_path = info.source:sub(2)
    local script_dir = script_path:match "(.*/)" or "./"
    return script_dir .. "libblink_cmp_fuzzy" .. get_lib_extension()
end

---Prompt the user before downloading the pre-built binary.
---@param callback fun(accepted: boolean) Called with the user's decision.
local function prompt_download(callback)
    if declined_download then
        callback(false)
        return
    end

    vim.schedule(function()
        vim.ui.select({ "Yes", "No" }, {
            prompt = "Refer: blink.cmp is not installed. Download the pre-built fuzzy matcher binary ("
                .. VERSION
                .. ")?",
            kind = "confirm",
        }, function(choice)
            local accepted = choice == "Yes"
            if not accepted then
                declined_download = true
            end
            callback(accepted)
        end)
    end)
end

---Download the pre-built binary for the current platform.
---@param lib_path string Where to write the library file.
---@param on_done fun(success: boolean, err: string|nil)
local function download_binary(lib_path, on_done)
    local triple = get_system_triple()
    if not triple then
        on_done(false, "System not supported for pre-built blink-fuzzy binaries.")
        return
    end

    if vim.fn.executable "curl" ~= 1 then
        on_done(false, "curl is not installed.")
        return
    end

    local url = string.format("%s/%s/%s%s", BASE_URL, VERSION, triple, get_lib_extension())
    is_downloading = true

    vim.notify("Refer: Downloading fuzzy matcher library...", vim.log.levels.INFO)

    vim.system({
        "curl",
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--create-dirs",
        "--output",
        lib_path,
        url,
    }, {}, function(out)
        is_downloading = false
        if out.code == 0 then
            vim.schedule(function()
                vim.notify("Refer: Fuzzy matcher downloaded successfully.", vim.log.levels.INFO)
            end)
            on_done(true, nil)
        else
            local err = (out.stderr or "unknown error")
            vim.schedule(function()
                vim.notify("Refer: Failed to download fuzzy matcher: " .. err, vim.log.levels.ERROR)
            end)
            on_done(false, err)
        end
    end)
end

---Attempt to load the fallback pre-built library directly via package.loadlib.
---@return table|nil module The loaded module, or nil if it could not be loaded.
local function load_fallback_lib()
    local lib_path = get_lib_path()
    if not vim.uv.fs_stat(lib_path) then
        return nil
    end

    local open_func, err = package.loadlib(lib_path, "luaopen_blink_cmp_fuzzy")
    if not open_func then
        if not is_downloading then
            vim.notify("Refer: Failed to load fuzzy lib: " .. (err or "unknown"), vim.log.levels.ERROR)
        end
        return nil
    end

    rust_module = open_func()
    has_loaded = true
    return rust_module
end

---Load the Rust module.
---@return table|nil module The loaded module or nil
local function load_module()
    if has_loaded and rust_module then
        return rust_module
    end

    if os.getenv "REFER_SKIP_DOWNLOAD" then
        return nil
    end

    local has_blink, blink = pcall(require, "blink.cmp.fuzzy.rust")
    if has_blink then
        rust_module = blink
        has_loaded = true
        return rust_module
    end

    if prepare_hook then
        local ok, result = pcall(prepare_hook)
        if ok and result then
            local retry_ok, mod = pcall(require, "blink.cmp.fuzzy.rust")
            if retry_ok then
                rust_module = mod
                has_loaded = true
                return rust_module
            end
        end
    end

    local fallback = load_fallback_lib()
    if fallback then
        return fallback
    end

    if is_downloading or declined_download then
        return nil
    end

    prompt_download(function(accepted)
        if not accepted then
            return
        end
        local lib_path = get_lib_path()
        download_binary(lib_path, function() end)
    end)

    return nil
end

---Check if blink is available.
---@return boolean available Whether the blink fuzzy matcher is available
function M.is_available()
    return load_module() ~= nil
end

---Register items with the fuzzy matcher
---@param id string Context ID (e.g. "refer")
---@param items table List of items with label and sortText fields
function M.set_provider_items(id, items)
    local mod = load_module()
    if not mod then
        return
    end

    mod.set_provider_items(id, items)
end

---Perform fuzzy search
---@param query string Search query
---@param id string Context ID
---@return table|nil matches List of matched items
---@return table|nil indices List of matched indices
function M.fuzzy(query, id)
    local mod = load_module()
    if not mod then
        return nil, nil
    end

    -- Blink fuzzy signature: fuzzy(query, query_len, providers_list, opts)
    return mod.fuzzy(query, #query, { id }, {
        max_typos = 1,
        use_frecency = true,
        use_proximity = false,
        nearby_words = {},
        match_suffix = false,
        snippet_score_offset = 0,
        sorts = { "score", "sort_text" },
    })
end

return M
