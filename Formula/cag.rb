# typed: false
# frozen_string_literal: true

class Cag < Formula
  desc "Unified CLI wrapper for AI agents (Claude, Gemini, Codex)"
  homepage "https://github.com/stanislavlysenko0912/cag"
  version "0.3.1"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_arm64.tar.gz"
      sha256 "856523d58b5b12039157ff9a6e6937d985e686497c075b76d67ea9342bc92403"

      def install
        bin.install "cag"
      end
    end

    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_x64.tar.gz"
      sha256 "d55ca5be348992c07204d8accff680a2bfd93e3af8ab315366b5c23a995183cd"

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
