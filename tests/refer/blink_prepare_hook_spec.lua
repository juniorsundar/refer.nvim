local stub = require "luassert.stub"

local prompt_calls = 0

-- reload refer.blink so its internal has_loaded/declined_download/is_downloading
-- module state is fresh for each test.
local function reload_blink()
    package.loaded["refer.blink"] = nil
    return require "refer.blink"
end

-- reload refer so setup re-plumbs the hook into the freshly-loaded refer.blink.
local function reload_refer()
    package.loaded["refer"] = nil
    return require "refer"
end

-- Install (or remove) the blink.cmp.fuzzy.rust native module. Pass `nil` to make
-- the require fail (simulating an installed-but-not-yet-prepared or absent
-- blink), or a table to make it succeed (simulating a prepared blink v1.X).
local function set_rust_module(mod)
    if mod == nil then
        package.loaded["blink.cmp.fuzzy.rust"] = nil
        package.preload["blink.cmp.fuzzy.rust"] = function()
            error "module not found"
        end
    else
        package.preload["blink.cmp.fuzzy.rust"] = nil
        package.loaded["blink.cmp.fuzzy.rust"] = mod
    end
end

local function clear_rust_module()
    package.loaded["blink.cmp.fuzzy.rust"] = nil
    package.preload["blink.cmp.fuzzy.rust"] = nil
end

-- The fallback-download prompt is dispatched via vim.schedule, so it does not
-- fire synchronously inside is_available(). Flush the event loop so a scheduled
-- prompt (if any) is observed by the prompt-call counter before asserting.
local function flush_prompt()
    vim.wait(1000, function()
        return prompt_calls > 0
    end, 10)
end

-- Drain any callbacks still scheduled by a prior test so they cannot leak into
-- the next test's stub/counter. Called with the stub reverted (no-op), so any
-- in-flight prompt callback does nothing and never increments prompt_calls.
local function drain()
    vim.wait(50, function()
        return false
    end, 5)
end

describe("refer.blink prepare hook", function()
    local getenv_stub
    local ui_select_stub
    local original_select

    before_each(function()
        prompt_calls = 0
        drain()

        getenv_stub = stub(os, "getenv", function(name)
            if name == "REFER_SKIP_DOWNLOAD" then
                return nil
            end
            return nil
        end)
        original_select = vim.ui.select
        ui_select_stub = stub(vim.ui, "select", function(_, _, _, on_choice)
            prompt_calls = prompt_calls + 1
            if on_choice then
                on_choice(nil, nil)
            end
        end)
        set_rust_module(nil)
    end)

    after_each(function()
        drain()
        if getenv_stub then
            getenv_stub:revert()
        end
        if ui_select_stub then
            ui_select_stub:revert()
        end
        if original_select then
            vim.ui.select = original_select
        end
        clear_rust_module()
        package.loaded["refer"] = nil
        package.loaded["refer.blink"] = nil
    end)

    it(
        "calls the hook when the native-module load fails, and retries the load on a truthy return (no prompt)",
        function()
            local hook_calls = 0
            local function make_rust()
                return {
                    set_provider_items = function() end,
                    fuzzy = function()
                        return {}, {}
                    end,
                }
            end

            local refer = reload_refer()
            reload_blink()
            set_rust_module(nil)

            refer.setup {
                blink_prepare = function()
                    hook_calls = hook_calls + 1
                    set_rust_module(make_rust())
                    return true
                end,
            }

            local blink = require "refer.blink"
            local available = blink.is_available()

            assert.is_true(available, "retry after a truthy hook should load the module")
            assert.are.equal(1, hook_calls, "the hook is called exactly once on a failing load")
            assert.are.equal(0, prompt_calls, "a truthy hook skips the download prompt")
        end
    )

    it("preserves the v1.X fast path: when the module loads on the first try, the hook is never called", function()
        local hook_calls = 0
        local rust = {
            set_provider_items = function() end,
            fuzzy = function()
                return {}, {}
            end,
        }
        set_rust_module(rust)

        local refer = reload_refer()
        reload_blink()
        refer.setup {
            blink_prepare = function()
                hook_calls = hook_calls + 1
                return true
            end,
        }

        local blink = require "refer.blink"
        assert.is_true(blink.is_available())
        assert.are.equal(0, hook_calls, "the hook is not called when the first load succeeds")
        assert.are.equal(0, prompt_calls, "no prompt when the module is already loaded")
    end)

    it("falls through to the download prompt when there is no hook (backward compatible)", function()
        local refer = reload_refer()
        reload_blink()
        set_rust_module(nil)

        refer.setup {}

        local blink = require "refer.blink"
        local available = blink.is_available()

        assert.is_false(available, "absent module + no hook leaves refer unavailable")
        flush_prompt()
        assert.are.equal(1, prompt_calls, "the fallback prompt fires once for users without a hook")
    end)

    it("falls through to the download prompt when the hook returns falsy", function()
        local hook_calls = 0
        local refer = reload_refer()
        reload_blink()
        set_rust_module(nil)

        refer.setup {
            blink_prepare = function()
                hook_calls = hook_calls + 1
                return false
            end,
        }

        local blink = require "refer.blink"
        local available = blink.is_available()

        assert.is_false(available, "falsy hook leaves refer unavailable")
        assert.are.equal(1, hook_calls, "the hook is called once on a failing load")
        flush_prompt()
        assert.are.equal(1, prompt_calls, "a falsy hook falls through to the download prompt")
    end)
end)
