.PHONY: clean test dev release
CLEAN_COV=if [ -e luacov.report.out ]; then rm luacov.report.out; fi; if [ -e luacov.stats.out ]; then rm luacov.stats.out; fi
PWD=$(shell pwd)

LUA_PATH := ./src/?.lua
LUA_PATH := $(LUA_PATH);$(PWD)/e/serializer/?.lua
LUA_PATH := $(LUA_PATH);$(PWD)/e/du-unit-testing/src/?.lua
LUA_PATH := $(LUA_PATH);$(PWD)/e/du-unit-testing/external/du-lua-examples/?.lua
LUA_PATH := $(LUA_PATH);$(PWD)/e/du-unit-testing/external/du-lua-examples/api-mockup/?.lua
LUA_PATH := $(LUA_PATH);$(PWD)/e/du-unit-testing/external/du-luac/lua/?.lua


all: release

lua_path:
	@echo "$(LUA_PATH)"

clean_cov:
	@$(CLEAN_COV)

clean_report:
	@if [ -d ./luacov-html ]; then rm -rf ./luacov-html; fi

clean: clean_cov clean_report
	@rm -rf out

test: clean
	@echo Runnings unit tests on du-stream
	@LUA_PATH="$(LUA_PATH)" busted . --exclude-pattern=".*serializer.*"
	@luacov
	@$(CLEAN_COV)

dev: test
	@LUA_PATH="$(LUA_PATH)" du-lua build --copy=development/Controller

