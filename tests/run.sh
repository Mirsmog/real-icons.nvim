#!/bin/sh
set -eu
test_root=$(mktemp -d "${TMPDIR:-/tmp}/real-icons-test.XXXXXX")
export XDG_CONFIG_HOME="$test_root/config"
export XDG_CACHE_HOME="$test_root/cache"
export XDG_DATA_HOME="$test_root/data"
export XDG_STATE_HOME="$test_root/state"
export REAL_ICONS_TEST_FILE="${1:-tests/run.lua}"
exec nvim --headless -i NONE -u tests/minimal_init.lua \
  -c 'lua local ok, err = xpcall(function() dofile(vim.env.REAL_ICONS_TEST_FILE) end, debug.traceback); if not ok then print(err); vim.cmd("cquit 1") end'
