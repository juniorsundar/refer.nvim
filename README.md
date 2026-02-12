<div align="center">

# refer.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/juniorsundar/refer.nvim/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

</div>

`refer.nvim` is a minimalist picker for Neovim.

It is designed to:
- **Be intuitive:** It shouldn't pull you out of your current context and meld in seamlessly with your workflow.
- **Be clean:** Minimalist UI without floating windows and noise, a lot like Emacs minibuffers.
- **Integrate:** With other plugins (use the fuzzy sorter used in your at-point completion in your selecter).
- **Functionally hackable:** While there is limited flexibility in the picker's aesthetics, it is functionally hackable in every way.

It is not designed to:
- **Be "blazingly fast":** Speed is relative. This is, in essense, a picker plugin. I am not developing a super-fast fuzzy sorter.

## Features

This plugin only provides you with a picker. I am not spending any energy to develop an optimised fuzzy sorter. There are already implementations out there that you can use. This plugin provides you with the ability to register these fuzzy sorter implementations.

There are already some sorters registered:
- **Blink:** Rust-based, extremely fast (Default for static lists) (Requires `blink.cmp` installed. Or else it will download just the library from GitHub.).
- **Native:** Vim's `matchfuzzy` (Vim is generous... `:h matchfuzzy()`.).
- **Mini:** Support for `mini.fuzzy` if installed (This supports strings with spaces in them, unlike the above two options.).
- **Lua:** Pure Lua fallback (Default for async file lists) (I kept this for posterity's sake. Its by no means the most optimal option. Also supports strings with spaces in them.).

## Requirements

- **Neovim 0.10+**
- **curl** (Required to download the pre-built Blink fuzzy matcher binary).
- **fd** (Required for the `Files` picker).
- **ripgrep** (Required for the `Grep` picker).

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "juniorsundar/refer.nvim",
    dependencies = {
        -- Optional:
        -- "saghen/blink.cmp", 
        -- "nvim-mini/mini.fuzzy", 
    },
    config = function()
        -- The plugin autoloads, but you can pass opts to setup.
        require("refer").setup(
        -- opts
        )
    end
}
```

## Commands

Use `:Refer <subcommand>` to launch pickers:

| Command       | Description                                  |
| ------------- | -------------------------------------------- |
| `Files`       | Fuzzy find files using `fd` (Async)          |
| `Grep`        | Live grep using `ripgrep` (Async)            |
| `Buffers`     | Switch between open buffers                  |
| `OldFiles`    | Browse recently opened files                 |
| `Commands`    | Execute Vim commands interactively           |
| `References`  | List LSP references for symbol under cursor  |
| `Definitions` | Go to LSP definition for symbol under cursor |

## Tutorials & Advanced Usage

### Replacing `vim.ui.select`
Use `refer` as the interface for `vim.ui.select` (used by code actions and plugins):

```lua
require("refer").setup_ui_select()
```

### Custom Keymaps
You can customize key bindings inside the picker window.

```lua
require("refer").setup({
    keymaps = {
        -- Bind to a built-in action name
        ["<C-x>"] = "close", 
        
        -- Or use a custom function
        ["<C-y>"] = function(selection, builtin)
             print("You selected: " .. selection)
             builtin.actions.close()
        end
    }
})
```

**Default Keymaps:**
- `<Tab>`: Complete selection (common prefix)
- `<CR>`: Select entry
- `<C-n>`/`<Down>`: Next item
- `<C-p>`/`<Up>`: Previous item
- `<C-v>`: Toggle preview
- `<C-s>`: Cycle sorters (blink -> lua -> native)
- `<C-q>`: Send to Quickfix list
- `<C-g>`: (EXPERIMENTAL - Requires a WIP plugin) Send to "Grep" buffer (Editable results)
- `<Esc>`/`<C-c>`: Close

### Bring Your Own Fuzzy (Custom Sorters)
You can define custom sorting algorithms. For example, a simple prefix matcher:

```lua
require("refer").setup({
    custom_sorters = {
        my_prefix_sorter = function(items, query)
            local matches = {}
            for _, item in ipairs(items) do
                if vim.startswith(item, query) then
                    table.insert(matches, item)
                end
            end
            return matches
        end,
    },
    -- Add to available sorters to allow cycling to it with <C-s>
    available_sorters = { "blink", "my_prefix_sorter", "lua" },
})
```

### Custom Parsers
Teach `refer` how to parse specific text formats to enable file preview and navigation. This is useful if you are piping custom logs or tool output into `refer`.

**Scenario:** You have input lines formatted like: `src/main.lua [Line 10, Col 5]`.

```lua
require("refer").setup({
    custom_parsers = {
        my_log_format = {
            -- Lua pattern with capture groups
            pattern = "^(.-)%s+%[Line (%d+), Col (%d+)%]",
            -- Map capture groups to keys ("filename", "lnum", "col", "content")
            keys = { "filename", "lnum", "col" },
            -- Optional type conversion
            types = { lnum = tonumber, col = tonumber },
        },
    }
})
```

## Configuration Reference

The default configuration with all available options:

```lua
require("refer").setup({
    -- General Settings
    max_height_percent = 0.4, -- Window height (0.1 - 1.0)
    min_height = 1,           -- Minimum lines
    
    -- Async Settings
    debounce_ms = 100,        -- Delay for async searching
    min_query_len = 2,        -- Min chars to start async search

    -- Sorting
    available_sorters = { "blink", "mini", "native", "lua" },
    default_sorter = "blink", 

    -- Preview Settings
    preview = {
        enabled = true,
        max_lines = 1000,
    },

    -- UI Customization
    ui = {
        mark_char = "●",
        mark_hl = "String",
        winhighlight = "Normal:Normal,FloatBorder:Normal,WinSeparator:Normal,StatusLine:Normal,StatusLineNC:Normal",
        highlights = {
            prompt = "Title",
            selection = "Visual",
            header = "WarningMsg", 
        },
    },

    -- Provider Configuration
    providers = {
        files = {
            ignored_dirs = { ".git", ".jj", "node_modules", ".cache" },
            find_command = { "fd", "-H", "--type", "f", "--color", "never" },
        },
        grep = {
            grep_command = { "rg", "--vimgrep", "--smart-case" },
        },
    },
    
    -- See "Tutorials" section for keymaps, custom_sorters, and custom_parsers
})
```
