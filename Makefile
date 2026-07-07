.PHONY: build run install local-install verify-install uninstall clean gen fmt hooks mcp-inspect test

NAME := cag
BUILD_DIR := build

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
BIN_DIR ?= $(LOCALAPPDATA)/cag
VERSION := $(shell powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content pubspec.yaml | Where-Object { $$_ -match '^version:' } | Select-Object -First 1) -replace '^version:\s*',''")
MKDIR = powershell -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Force -Path '$(1)' | Out-Null"
COPY = powershell -NoProfile -ExecutionPolicy Bypass -Command "Copy-Item -Force '$(1)' '$(2)'"
REMOVE = powershell -NoProfile -ExecutionPolicy Bypass -Command "Remove-Item -Force -Recurse '$(1)' -ErrorAction SilentlyContinue"
RUN_BIN = "$(subst /,\,$(BIN_DIR)/$(NAME)$(EXE_EXT))"
UNQUARANTINE =
else
UNAME_S := $(shell uname -s)
EXE_EXT :=
VERSION := $(shell awk '/^version:/{print $$2}' pubspec.yaml)
ifeq ($(UNAME_S),Darwin)
BIN_DIR ?= $(HOME)/bin
UNQUARANTINE = xattr -dr com.apple.quarantine "$(INSTALL_BIN)" 2>/dev/null || true
else
BIN_DIR ?= /usr/local/bin
UNQUARANTINE =
endif
MKDIR = mkdir -p "$(1)"
COPY = cp "$(1)" "$(2)"
REMOVE = rm -rf "$(1)"
RUN_BIN = "$(BIN_DIR)/$(NAME)"
endif

BUILD_BIN := $(BUILD_DIR)/$(NAME)$(EXE_EXT)
INSTALL_BIN := $(BIN_DIR)/$(NAME)$(EXE_EXT)

ARGS ?=

gen:
	@fvm dart run tool/gen_schema.dart

build: gen
	@$(call MKDIR,$(BUILD_DIR))
	fvm dart compile exe bin/$(NAME).dart -o $(BUILD_BIN) --define=APP_VERSION=$(VERSION)
	@echo "Built: $(BUILD_BIN)"

run:
	fvm dart run bin/$(NAME).dart $(ARGS)

test: gen
	fvm dart test

fmt:
	fvm dart format .

hooks:
	git config core.hooksPath .githooks

install: build
	@$(call MKDIR,$(BIN_DIR))
	@$(call COPY,$(BUILD_BIN),$(INSTALL_BIN))
	@$(UNQUARANTINE)
	@echo "Installed to $(INSTALL_BIN)"

local-install: install verify-install

verify-install:
	$(RUN_BIN) --version
	$(RUN_BIN) detect
	$(RUN_BIN) --help

uninstall:
	@$(call REMOVE,$(INSTALL_BIN))
	@echo "Removed $(INSTALL_BIN)"

mcp-inspect:
	npx -y @modelcontextprotocol/inspector fvm dart run bin/$(NAME).dart mcp

clean:
	@$(call REMOVE,$(BUILD_DIR))
	@echo "Cleaned"
