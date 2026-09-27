cask "clonie" do
  version "1.1.0"
  sha256 "10f8b0ef6e9b8c41be6cfc4d90e834a07f74a584127af05a4ce98dd5dd5b2329"

  url "https://github.com/qoal1201/clonie-preview/releases/download/v#{version}/Clonie-#{version}-arm64-notarized.zip"
  name "Clonie"
  desc "Local Markdown workspace with on-device context search"
  homepage "https://github.com/qoal1201/clonie-preview"

  livecheck do
    skip "Cask is updated alongside GitHub releases"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Clonie.app"

  caveats <<~EOS
    This release is Developer ID signed and notarized by Apple.
    macOS first-launch confirmation and audio permissions still require your approval.
  EOS
end
