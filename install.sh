#!/bin/bash
set -euo pipefail

REPO="stanislavlysenko0912/cag"
INSTALL_DIR="${CAG_INSTALL_DIR:-/usr/local/bin}"
VERSION="${1:-latest}"

info() { echo -e "\033[1;34m=>\033[0m $1"; }
error() { echo -e "\033[1;31mError:\033[0m $1" >&2; exit 1; }
success() { echo -e "\033[1;32m=>\033[0m $1"; }

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os="macos" ;;
    Linux) os="linux" ;;
    *) error "Unsupported OS: $os" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) error "Unsupported architecture: $arch" ;;
  esac

  if [[ "$os" == "linux" && "$arch" == "arm64" ]]; then
    error "Linux arm64 is not currently supported"
  fi

  echo "${os}_${arch}"
}

get_latest_version() {
  curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"tag_name"' \
    | sed -E 's/.*"([^"]+)".*/\1/'
}

main() {
  info "Detecting platform..."
  local platform
  platform="$(detect_platform)"
  info "Platform: $platform"

  if [[ "$VERSION" == "latest" ]]; then
    info "Fetching latest version..."
    VERSION="$(get_latest_version)"
  fi
  info "Version: $VERSION"

  local url="https://github.com/${REPO}/releases/download/${VERSION}/cag_${platform}.tar.gz"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  info "Downloading $url..."
  curl -fsSL "$url" -o "$TMP_DIR/cag.tar.gz"

  info "Extracting..."
  tar -xzf "$TMP_DIR/cag.tar.gz" -C "$TMP_DIR"

  info "Installing to $INSTALL_DIR..."
  if [[ -w "$INSTALL_DIR" ]]; then
    mv "$TMP_DIR/cag" "$INSTALL_DIR/cag"
  else
    sudo mv "$TMP_DIR/cag" "$INSTALL_DIR/cag"
  fi
  chmod +x "$INSTALL_DIR/cag"

  success "cag $VERSION installed successfully!"
  info "Run 'cag --help' to get started"
}

main "$@"
