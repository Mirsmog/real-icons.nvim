.PHONY: test test-integration

test:
	sh tests/run.sh

test-integration:
	sh tests/run.sh tests/integrations.lua
	sh tests/run.sh tests/nvim_tree.lua
