# typed: false
# frozen_string_literal: true

class Cag < Formula
  desc "Unified CLI wrapper for AI agents (Claude, Gemini, Codex)"
  homepage "https://github.com/stanislavlysenko0912/cag"
  version "0.4.0"
  license "MIT"

  on_macos do
    on_arm do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_arm64.tar.gz"
      sha256 "65e5722907479f569f858875343ff82633812dbac7345599a11ac65bcf043e13"

      def install
        bin.install "cag"
      end
    end

    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_macos_x64.tar.gz"
      sha256 "d4e33772afb1ecce8ddabaf4ed125c54b6d575fa146b2052b686007b3bf77afc"

      def install
        bin.install "cag"
      end
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/stanislavlysenko0912/cag/releases/download/v#{version}/cag_linux_x64.tar.gz"
      sha256 "65205c59a103bf9820286a399c233426fbaa68031972b9edb85706edba568027"

      def install
        bin.install "cag"
      end
    end
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cag --version")
  end
end
