# Contributing

Bug reports and pull requests are welcome. For a bug report, include steps to
reproduce, your terminal and Neovim versions, and the output of
`:RealIcons report` and `:checkhealth real-icons`. Review diagnostics before
sharing them.

## Tests

Run commands from the repository root with Neovim 0.10+ installed. ImageMagick
(`magick`) enables the SVG conversion checks.

```sh
make test
```

The unit and regression suites cover configuration, theme discovery, icon
resolution, caching, commands, fallback behavior, and integration adapters.
Each run uses temporary config, data, cache, and state directories.

To test against real integration plugins, provide local checkouts with these
directory names:

```text
checkouts/
  bufferline/
  devicons/
  lualine/
  nvim_tree/
  plenary/
  telescope/
```

```sh
REAL_ICONS_TEST_DEPS=/path/to/checkouts make test-integration
```

These tests do not install or update dependencies. They check Lualine and
Bufferline setup order, file context and spacing, Telescope entries, and
nvim-tree refreshes after cold-cache conversion, pack changes, and colorscheme
changes. The nvim-tree checks require ImageMagick.

## Changes

Keep changes focused and include a regression test for bug fixes. Update
`doc/real-icons.txt` when changing configuration, commands, or the Lua API.
Visual changes should also be checked in Ghostty or Kitty; headless tests
cannot verify the terminal's image rendering.
