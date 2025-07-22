# neovide-terminals

A smart terminal management plugin for Neovide that provides intelligent terminal handling, project-aware directory switching, and advanced terminal features.

## Features

- **Smart Directory Detection**: Automatically opens terminals in git root or current file directory
- **Named Terminal Management**: Create and manage multiple named terminals (Git, Dev Server, Tests, Claude)
- **Scroll Position Memory**: Remembers terminal scroll positions when switching between terminals
- **Terminal Tab Management**: Cycle through terminals like browser tabs
- **Send Code to Terminal**: Send current line or visual selection to terminal
- **Floating Titles**: Beautiful terminal titles showing terminal names
- **Full Screen Floating**: Distraction-free full-screen floating terminals

## Requirements

- Neovim >= 0.8.0
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "booka66/nvim-smart-terminals",
  dependencies = { "akinsho/toggleterm.nvim" },
  config = function()
    require("smart-terminals").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "booka66/nvim-smart-terminals",
  requires = { "akinsho/toggleterm.nvim" },
  config = function()
    require("smart-terminals").setup()
  end,
}
```

## Key Mappings

### Terminal Management

| Key               | Mode  | Description                       |
| ----------------- | ----- | --------------------------------- |
| `<M-t>` / `<D-t>` | n,i,t | Create new terminal tab           |
| `<C-Tab>`         | n,i,t | Cycle through terminals           |
| `<C-S-Tab>`       | n,i,t | Cycle backwards through terminals |
| `<C-\>`           | n,i,t | Toggle current terminal           |

### Terminal Control (Terminal Mode)

| Key                         | Mode | Description                  |
| --------------------------- | ---- | ---------------------------- |
| `<C-w>` / `<D-w>` / `<M-w>` | t    | Close current terminal       |
| `<C-h/j/k/l>`               | t    | Navigate to adjacent windows |
| `<C-x>`                     | t    | Exit terminal mode           |

### Quick Terminal Types

| Key          | Mode | Description                                  |
| ------------ | ---- | -------------------------------------------- |
| `<leader>tg` | n    | Git terminal                                 |
| `<leader>td` | n    | Dev server terminal                          |
| `<leader>tt` | n    | Test terminal                                |
| `<leader>tc` | n    | Claude terminal (auto-runs `claude` command) |

### Advanced Features

| Key          | Mode | Description                        |
| ------------ | ---- | ---------------------------------- |
| `<leader>ti` | n    | Show terminal info                 |
| `<leader>tn` | n    | Rename current terminal            |
| `<leader>tK` | n    | Kill all terminals                 |
| `<leader>tp` | n    | Pick terminal (fuzzy finder style) |

## Configuration

### Basic Setup

```lua
require("smart-terminals").setup()
```

### ToggleTerm Integration

This plugin is designed to work alongside toggleterm.nvim. Here's a recommended toggleterm configuration:

```lua
{
  "akinsho/toggleterm.nvim",
  version = "*",
  opts = {
    size = 20,
    open_mapping = [[<c-\>]],
    hide_numbers = true,
    shade_terminals = true,
    shading_factor = 2,
    start_in_insert = true,
    insert_mappings = true,
    terminal_mappings = true,
    persist_size = true,
    persist_mode = true,
    direction = "float",
    close_on_exit = true,
    shell = vim.o.shell,
    auto_scroll = false,
    float_opts = {
      border = "none",
      row = 0,
      col = 0,
      width = function() return vim.o.columns end,
      height = function() return vim.o.lines end,
      winblend = 3,
      highlights = {
        border = "FloatBorder",
        background = "Normal",
      },
    },
  },
}
```

## Smart Features

### Directory Detection

The plugin automatically detects the best directory for new terminals:

1. If in a git repository, opens terminal in git root
2. Otherwise, uses current file's directory
3. Falls back to current working directory

### Named Terminals

Create specific terminals for different purposes:

- **Git terminal**: For git operations
- **Dev Server terminal**: For running development servers
- **Test terminal**: For running tests
- **Claude terminal**: Automatically runs the `claude` command

## API

You can also use the plugin programmatically:

```lua
local smart_terminals = require("smart-terminals")

-- Create specific terminal types
smart_terminals.create_git_terminal()
smart_terminals.create_dev_terminal()
smart_terminals.create_test_terminal()
smart_terminals.create_claude_terminal()

-- Terminal management
smart_terminals.new_terminal("Custom Name", "/custom/path")
smart_terminals.toggle_current_terminal()
smart_terminals.close_current_terminal()
smart_terminals.cycle_terminals()

-- Utility functions
smart_terminals.show_terminal_info()
smart_terminals.send_line_to_terminal()
smart_terminals.send_selection_to_terminal()
smart_terminals.rename_terminal()
smart_terminals.kill_all_terminals()
smart_terminals.pick_terminal()
smart_terminals.run_project_command()
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License
