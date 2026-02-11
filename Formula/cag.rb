# typed: false
# frozen_string_literal: true

class Cag < Formula
  desc "Unified CLI wrapper for AI agents (Claude, Gemini, Codex)"
  homepage "https://github.com/stanislavlysenko0912/cag"
  version "0.2.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_arm64.tar.gz"
      sha256 "faa6688747beeaac7da3adcfa6bde66b8ed54b2d9cc371177b37c5de4a44c315"

      def install
        bin.install "cag"
      end
    end

    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_x64.tar.gz"
      sha256 "3a4886a23acd117284c02aeb99a0db00755fef0d9cd0466883c3f095fad62464"

      def install
        bin.install "cag"
      end
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_linux_x64.tar.gz"
      sha256 "SHA256_LINUX_X64"

      def install
        bin.install "cag"
      end
    end
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cag --version")
  end
end
