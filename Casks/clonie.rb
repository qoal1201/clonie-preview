cask "clonie" do
  version "20260917-clonie1"
  sha256 "221d12730bd7ae669dfb594cf5e6be1e4ebbf08b197532d4f6ba45d0d9cbac79"

  url "https://github.com/qoal1201/clonie-preview/releases/download/preview-#{version}/Clonie-preview-#{version}-arm64.zip"
  name "Clonie"
  desc "Local Markdown workspace with on-device context search"
  homepage "https://github.com/qoal1201/clonie-preview"

  livecheck do
    skip "Preview builds are updated manually"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Clonie-preview-#{version}-arm64/Clonie.app"

  caveats <<~EOS
    This preview is not notarized by Apple. macOS may require approval in
    System Settings > Privacy & Security before the first launch.
    The installed app is Clonie.app. An existing Ghostbar.app is left untouched.
  EOS
end
