.PHONY: test

test:
	nvim --headless -u tests/minimal_init.lua -c 'lua dofile("tests/run.lua")'
