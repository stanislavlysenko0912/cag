.PHONY: build run install uninstall clean gen fmt hooks

NAME := cag
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
BIN_DIR ?= $(HOME)/bin
else
BIN_DIR ?= /usr/local/bin
endif
BUILD_DIR := build
VERSION := $(shell awk '/^version:/{print $$2}' pubspec.yaml)

gen:
	@fvm dart run tool/gen_schema.dart

build: gen
	@mkdir -p $(BUILD_DIR)
	fvm dart compile exe bin/$(NAME).dart -o $(BUILD_DIR)/$(NAME) --define=APP_VERSION=$(VERSION)
	@echo "Built: $(BUILD_DIR)/$(NAME)"

run:
	fvm dart run bin/$(NAME).dart

fmt:
	fvm dart format .

hooks:
	git config core.hooksPath .githooks

install:
	@mkdir -p $(BIN_DIR)
	@cp $(BUILD_DIR)/$(NAME) $(BIN_DIR)/$(NAME)
	@if [ "$$(uname -s)" = "Darwin" ]; then xattr -dr com.apple.quarantine $(BIN_DIR)/$(NAME) 2>/dev/null || true; fi
	@echo "Installed to $(BIN_DIR)/$(NAME)"

uninstall:
	@rm -f $(BIN_DIR)/$(NAME)
	@echo "Removed $(BIN_DIR)/$(NAME)"

clean:
	@rm -rf $(BUILD_DIR)
	@echo "Cleaned"
