# typed: false
# frozen_string_literal: true

class Cag < Formula
  desc "Unified CLI wrapper for AI agents (Claude, Gemini, Codex)"
  homepage "https://github.com/stanislavlysenko0912/cag"
  version "0.2.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_arm64.tar.gz"
      sha256 "4eed7360bd75a50e5a0f3ca395273838798cd127b7cf64dac41d0c2450662d1c"

      def install
        bin.install "cag"
      end
    end

    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_x64.tar.gz"
      sha256 "f0027c0daf44d869491c0c569b4b289ff3828e4fdd6b9fe352b7dfbea229d4f0"

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
