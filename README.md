# real-icons.nvim

Graphical file icons for Neovim terminal UIs.

`real-icons.nvim` renders real PNG icons in the terminal through Kitty Graphics
Protocol Unicode placeholders. It is designed for Ghostty first, including tmux
passthrough support, with glyph fallback for unsupported terminals.

## Status

The rendering path is working in Ghostty and Ghostty inside tmux. The public API,
pack installer, cache pipeline, and integrations are still stabilizing.

## Requirements

- Neovim 0.10+
- Ghostty
- `termguicolors`
- `magick` from ImageMagick for SVG icon packs
- `curl` and `tar` for `:RealIconsInstallPack material`

For tmux:

```tmux
set -g default-terminal "tmux-256color"
set -gq terminal-overrides[1] "*:Tc"
set -gq terminal-features[3] "xterm-ghostty:RGB"
set -g allow-passthrough on
```

## Installation

With lazy.nvim:

```lua
{
  "real-icons/real-icons.nvim",
  build = ":RealIconsInstallPack material",
  opts = {
    pack = "material",
    integrations = {
      fzf_lua = false,
      mini_files = false,
      neo_tree = false,
      nvim_tree = false,
      telescope = true,
      telescope_file_browser = true,
      oil = false,
    },
  },
}
```

For `telescope-file-browser.nvim`, wire the entry maker into the extension
configuration:

```lua
{
  "nvim-telescope/telescope-file-browser.nvim",
  dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
  config = function()
    require("telescope").setup({
      extensions = {
        file_browser = {
          disable_devicons = true,
          entry_maker = require("real-icons.integrations.telescope_file_browser").entry_maker,
        },
      },
    })
    require("telescope").load_extension("file_browser")
  end,
}
```

For local development:

```lua
{
  dir = "/path/to/real-icons",
  name = "real-icons.nvim",
  lazy = false,
  opts = {
    pack = "material",
    integrations = {
      telescope = true,
      telescope_file_browser = true,
    },
  },
}
```

## Commands

```vim
:RealIconsHealth
:RealIconsDemo
:RealIconsInstallPack material
:RealIconsBuildCache
:RealIconsClearCache
```

`RealIconsInstallPack material` downloads the published `material-icon-theme`
npm tarball and stores it under `stdpath("data")/real-icons/packs/material`.
SVG icons are converted into PNG files lazily under
`stdpath("cache")/real-icons`.

## Configuration

```lua
require("real-icons").setup({
  pack = "material",
  size = {
    cols = 2,
    rows = 1,
    pixels = 64,
    padding = 0,
    trim = false,
  },
  fallback = {
    enabled = true,
    provider = "auto",
  },
  integrations = {
    fzf_lua = false,
    mini_files = false,
    neo_tree = false,
    nvim_tree = false,
    telescope = true,
    telescope_file_browser = true,
    oil = false,
  },
})
```

If the Material pack is not installed, `real-icons.nvim` uses a small bundled
fallback pack.

Icon sharpness depends on the raster size sent to the terminal and on the
terminal cell box where it is displayed. `cols` and `rows` reserve terminal
cells, while `pixels` controls the generated PNG size.

The default keeps SVG icons as sources and rasterizes them into a high-density
PNG cache. This avoids early loss of detail:

```lua
require("real-icons").setup({
  size = {
    cols = 2,
    rows = 1,
    pixels = 64,
    padding = 0,
    trim = false,
  },
})
```

If an icon pack has too much transparent padding, use `trim = true`. If icons
look too large after trimming, add `padding = 4` or `padding = 6`. After changing
these values, run `:RealIconsClearCache material` or let the plugin create a new
cache variant.

## API

```lua
local icons = require("real-icons")

local icon = icons.get(path, {
  is_dir = false,
  filetype = "lua",
})

icons.render(bufnr, row, col, icon)
```

Capability detection:

```lua
local icons = require("real-icons")

if icons.is_supported() then
  print(icons.backend())
end

vim.print(icons.capabilities())
```

## Telescope

Telescope core file pickers such as `oldfiles`, `find_files`, and `git_files`
use `telescope.make_entry.gen_from_file()` internally. Enable the core
integration to replace that file entry maker with a real-icons version:

```lua
require("real-icons").setup({
  integrations = {
    telescope = true,
  },
})
```

`telescope-file-browser.nvim` is a separate extension with its own entry maker,
so it also needs the extension-specific hook:

```lua
require("telescope").setup({
  extensions = {
    file_browser = {
      disable_devicons = true,
      entry_maker = require("real-icons.integrations.telescope_file_browser").entry_maker,
    },
  },
})
```

## fzf-lua

`fzf-lua` renders entries inside an fzf terminal, so the integration uses ANSI
foreground colors for Kitty placeholders and keeps fzf-lua's file parser
compatible by putting the icon before its metadata delimiter.

Automatic setup:

```lua
require("real-icons").setup({
  integrations = {
    fzf_lua = true,
  },
})
```

Manual setup, useful when you already own the `fzf-lua` config:

```lua
require("fzf-lua").setup(require("real-icons.integrations.fzf_lua").opts())
```

The first adapter covers `files`, `oldfiles`, `history`, `git_files`,
`git_diff`, `args`, and `complete_file`.

## neo-tree.nvim

Automatic setup patches `neo-tree`'s default icon provider before its config is
merged:

```lua
require("real-icons").setup({
  integrations = {
    neo_tree = true,
  },
})
```

Manual setup, useful when you already own the `neo-tree` config:

```lua
require("neo-tree").setup(require("real-icons.integrations.neo_tree").opts())
```

The adapter uses `default_component_configs.icon.provider`, so normal neo-tree
renderers, git status, diagnostics, modified markers, and selection markers stay
in neo-tree.

## mini.files

Manual setup:

```lua
require("mini.files").setup(require("real-icons.integrations.mini_files").opts())
```

Automatic setup can be enabled before `mini.files.setup()`:

```lua
require("real-icons").setup({
  integrations = {
    mini_files = true,
  },
})
```

The adapter uses `content.prefix`, which is the official `mini.files` hook for
text shown before entry names.

## nvim-tree.lua

Enable the adapter before or during `nvim-tree.lua` setup:

```lua
require("real-icons").setup({
  integrations = {
    nvim_tree = true,
  },
})
```

The adapter patches `nvim-tree`'s renderer builder and only replaces the file
or folder icon segment. Git, diagnostics, opened, hidden, modified, bookmark,
and clipboard decorators remain owned by `nvim-tree`.

## Integrating A File Explorer

Graphical file explorers should either use a native entry/display hook or call
`render()` for buffer-based UIs. Telescope uses a native `entry_maker`, because
it must reserve the icon column while building result rows.

For custom buffer-based UIs:

```lua
local ok, icons = pcall(require, "real-icons")

if ok and icons.is_supported() then
  local icon = icons.get(entry.path, { is_dir = entry.is_dir })
  icons.render(bufnr, lnum - 1, 0, icon)
else
  local fallback = icon.fallback
end
```

## Icon Packs

Default pack target:

- Material Icon Theme
- Source: https://github.com/material-extensions/vscode-material-icon-theme
- Package: https://www.npmjs.com/package/material-icon-theme
- License: MIT

The plugin code is MIT licensed. Installed packs keep their upstream licenses
and are stored in the user's data directory.

### Local VS Code Icon Themes

Any local VS Code icon theme can be used as a pack. This is useful for private
or commercial packs that should not be vendored into this repository.

```lua
require("real-icons").setup({
  pack = "flow",
  packs = {
    flow = {
      type = "vscode",
      path = vim.fn.expand("~/.vscode-oss/extensions/thang-nm.flow-icons-2.0.3"),
      theme = "flow-deep",
      license = "personal",
    },
  },
})
```

If `theme` is omitted, the first icon theme from the extension `package.json`
is used. You can also point directly at a manifest:

```lua
packs = {
  flow = {
    type = "vscode",
    path = "/path/to/flow-icons",
    manifest = "dim.json",
  },
}
```

### Simple Custom Packs

For a small local icon folder, use the simple loader:

```lua
require("real-icons").setup({
  pack = "my-icons",
  packs = {
    ["my-icons"] = {
      type = "simple",
      path = "~/icons",
      file = "file.svg",
      folder = "folder.svg",
      extensions = {
        lua = "lua.svg",
        ts = "typescript.svg",
        md = "markdown.svg",
      },
      filenames = {
        ["package.json"] = "nodejs.svg",
      },
      folders = {
        src = "folder-src.svg",
      },
    },
  },
})
```

### Overrides

Overrides sit above the active pack and are useful for replacing a few icons:

```lua
require("real-icons").setup({
  pack = "material",
  overrides = {
    extensions = {
      lua = "~/icons/custom-lua.svg",
    },
    filenames = {
      [".env"] = "~/icons/env.svg",
    },
    folders = {
      node_modules = "~/icons/node_modules.svg",
    },
  },
})
```

## How It Works

1. Resolve a path to an icon key using VS Code icon theme mappings.
2. Convert the source SVG to a cached PNG at the configured pixel size.
3. Upload the PNG to Ghostty using Kitty Graphics Protocol.
4. Place a `U+10EEEE` Unicode placeholder in the Neovim grid with an image id
   encoded in the foreground color.
5. In tmux, wrap the graphics upload in tmux DCS passthrough.

This makes the icon move with the text grid instead of relying on absolute
pixel placement.
