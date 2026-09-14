# Demo assets

Recorded in Ghostty with Neovim. Screenshots are 1794 x 1183; the H.264 video
is 1794 x 1184 at 30 fps. The extra video row pads the frame to an even height.

| File | Content |
| --- | --- |
| `preview.gif` | Workspace, Telescope, pack preview, and switch to Flow Deep |
| `demo.mp4` | Full 69-second demonstration |
| `pack-picker.png` | Flow Deep preview in the pack picker |
| `nvim-tree.png` | Flow Deep in nvim-tree, Bufferline, and Lualine |
| `workspace-flow.png` | Flow Deep with Catppuccin Mocha |
| `workspace-light.png` | Material Icon Theme with Catppuccin Latte |

The GIF is a 20.5-second excerpt beginning at 6.5 seconds, after the initial
icon conversion. To regenerate it from this video, with a new output path:

```sh
ffmpeg -n -ss 6.5 -t 20.5 -i demo.mp4 \
  -filter_complex 'fps=12,scale=1280:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle' \
  -loop 0 preview-new.gif
```

Icon packs: [Material Icon Theme](https://github.com/material-extensions/vscode-material-icon-theme)
and [Flow Icons](https://github.com/thang-nm/Flow-Icons).
Editor colors: [Catppuccin](https://github.com/catppuccin/nvim).
Upstream projects retain their respective licenses.
