<div align="center">

# refer.nvim

*"Not capable enough to [consult](https://github.com/minad/consult), but everything your need to refer"*

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/juniorsundar/refer.nvim/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

</div>

## Introduction

### Gallery

#### Commands

https://github.com/user-attachments/assets/d441844b-12ef-45a8-b2d4-560f8d7e6f10

#### Files (`fd`) and Quickfix

https://github.com/user-attachments/assets/2f91247d-5db0-42e6-b487-b97abb5e8b86

#### LSP

https://github.com/user-attachments/assets/3d31ddb8-abda-43c9-b62e-4b2d5b3ec890

### About

`refer.nvim` is a minimalist picker for Neovim.

It is designed to:

- **Be intuitive:** It shouldn't pull you out of your current context and meld in
  seamlessly with your workflow.  
- **Be clean:** Minimalist UI without floating windows and noise, a lot like
  Emacs minibuffers.  
- **Integrate:** With other plugins (use the fuzzy sorter used in your at-point
  completion in your selecter).  
- **Functionally hackable:** While there is limited flexibility in the picker's
  aesthetics, it is functionally hackable in every way.  

It is not designed to:

- **Be "blazingly fast":** Speed is relative. This is, in essense, a picker
  plugin. I am not developing a super-fast fuzzy sorter.  

## Features

This plugin only provides you with a picker. I am not spending any energy to
develop an optimised fuzzy sorter. There are already implementations out there
that you can use. This plugin provides you with the ability to register these
fuzzy sorter implementations.

There are already some sorters registered:

- **Blink:** Rust-based, extremely fast (Default for static lists) (Requires
  `blink.cmp` installed. Or else it will download just the library from
  GitHub.).  
- **Native:** Vim's `matchfuzzy` (Vim is generous... `:h matchfuzzy()`.).  
- **Mini:** Support for `mini.fuzzy` if installed (This supports strings with
  spaces in them, unlike the above two options.).  
- **Lua:** Pure Lua fallback (Default for async file lists) (I kept this for
  posterity's sake. Its by no means the most optimal option. Also supports
  strings with spaces in them.).  

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
| `Implementations` | Go to LSP implementation for symbol under cursor |
| `Declarations` | Go to LSP declaration for symbol under cursor |

## Tutorials & Advanced Usage

- [Replacing `vim.ui.select`](#replacing-vimuiselect)
- [Custom Keymaps](#custom-keymaps)
- [Bring Your Own Fuzzy (Custom Sorters)](#bring-your-own-fuzzy-custom-sorters)
- [Custom Parsers](#custom-parsers)
- [Customizing File Search](#customizing-file-search-using-find)
- [Customizing Grep](#customizing-grep-using-grep)
- [Creating Custom Pickers](#creating-custom-pickers)
  - [Static List Picker](#static-list-picker)
  - [Async Command Picker](#async-command-picker)
  - [Enabling Previews for Custom Items](#enabling-previews-for-custom-items)

### Replacing `vim.ui.select`
Use `refer` as the interface for `vim.ui.select` (used by code actions and
plugins):

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
- `<C-u>`: Scroll preview up
- `<C-d>`: Scroll preview down
- `<C-s>`: Cycle sorters (blink -> lua -> native)
- `<C-q>`: Send to Quickfix list  
- `<C-g>`: (EXPERIMENTAL - Requires a WIP plugin) Send to "Grep" buffer
  (Editable results)  
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
Teach `refer` how to parse specific text formats to enable file preview and
navigation. This is useful if you are piping custom logs or tool output into
`refer`.

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

### Customizing File Search (Using `find`)
By default, `refer` uses `fd`. If you prefer standard `find`, you can provide a
custom command generator function.

```lua
require("refer").setup({
    providers = {
        files = {
            -- Return the command as a table of strings
            find_command = function(query)
                return { "find", ".", "-type", "f", "-name", "*" .. query .. "*" }
            end
        }
    }
})
```

### Customizing Grep (Using `grep`)
By default, `refer` uses `rg` (ripgrep). If you prefer standard `grep`, you can
provide a custom command generator function.

```lua
require("refer").setup({
    providers = {
        grep = {
            -- Return the command as a table of strings
            grep_command = function(query)
                return { "grep", "-rnI", query, "." }
            end
        }
    }
})
```

### Creating Custom Pickers
#### Static List Picker

```lua
local refer = require("refer")

refer.pick(
    { "Option A", "Option B", "Option C" },
    function(item)
        print("You picked: " .. item)
    end,
    {
        prompt = "Pick one > ",
        -- Custom keymaps for this picker
        keymaps = {
            ["<C-d>"] = function(selection, builtin)
                print("Deleted: " .. selection)
                builtin.actions.close()
            end
        }
    }
)
```

#### Async Command Picker
Create a picker that runs a shell command based on your query (e.g., `locate`).

```lua
local refer = require("refer")

refer.pick_async(
    function(query)
        -- Return the command to run as a table of strings
        -- Return nil to stop/wait (e.g. if query is too short)
        if #query < 3 then return nil end
        return { "locate", query }
    end,
    function(selection)
        vim.cmd("edit " .. selection)
    end,
    {
        prompt = "Locate > ",
        debounce_ms = 200,
    }
)
```

#### Enabling Previews for Custom Items
Create a picker with custom string formats and teach `refer` how to parse them
so the built-in file previewer works.

```lua
local refer = require("refer")
refer.pick(
    {
        -- Alternate format as col:lnum:filename
        "10:5:lua/refer/picker.lua",
        "20:1:README.md",
    },
    function(selection, data)
        if data and data.filename then
            vim.cmd("edit " .. data.filename)
            vim.api.nvim_win_set_cursor(0, {data.lnum, data.col - 1})
        end
    end,
    {
        prompt = "Navigate > ",
        preview = { enabled = true },
        
        -- Custom parser for "row:col:filename"
        parser = function(selection)
            local lnum, col, filename = selection:match("^(%d+):(%d+):(.+)$")
            if filename then
                return {
                    filename = filename,
                    lnum = tonumber(lnum),
                    col = tonumber(col)
                }
            end
            return nil
        end
    }
)
```

#### Decoupling Choices from Preview

Sometimes you want the preview to correspond to something unrelated to the
choice currently under selection. For example, you want to create a picker to
move through the headings of a markdown file. You want the selections to be the
heading text, but you want the preview to be where in the markdown file the
heading is found.


```lua
local refer = require("refer")
local api = vim.api

if vim.bo.filetype ~= "markdown" then
    return
end

local bufnr = api.nvim_get_current_buf()
local filename = api.nvim_buf_get_name(bufnr)
local lines = api.nvim_buf_get_lines(bufnr, 0, -1, false)

local choices = {}
local lookup = {}

for lnum, line in ipairs(lines) do
    local hashes, title = line:match("^(#+)%s+(.+)$")
    if hashes then
        local level = #hashes
        local indent = string.rep("  ", level - 1)
        local display_text = indent .. title
        if not lookup[display_text] then
            table.insert(choices, display_text)
            lookup[display_text] = lnum
        end
    end
end

refer.pick(
    choices,
    function(selection)
        local lnum = lookup[selection]
        if lnum then
            api.nvim_win_set_cursor(0, {lnum, 0})
        end
    end,
    {
        prompt = "Outline > ",
        preview = { enabled = true },
        
        parser = function(selection)
            local lnum = lookup[selection]
            if lnum then
                return {
                    filename = filename,
                    lnum = lnum,
                    col = 1
                }
            end
            return nil
        end
    }
)
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
