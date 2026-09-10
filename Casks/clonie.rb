cask "clonie" do
  version "20260910"
  sha256 "48336eac1f3ab07a99d4c515c2d143b1894d6cfbabfceb5e8af2797cec89d4dc"

  url "https://github.com/qoal1201/clonie-preview/releases/download/preview-#{version}/Clonie-preview-#{version}-arm64.zip"
  name "Clonie"
  desc "Local Markdown workspace with on-device context search"
  homepage "https://github.com/qoal1201/clonie-preview"

  livecheck do
    skip "Preview builds are updated manually"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Clonie-preview-#{version}-arm64/Ghostbar.app"

  caveats <<~EOS
    This preview is not notarized by Apple. macOS may require approval in
    System Settings > Privacy & Security before the first launch.
    The installed app is currently named Ghostbar.app.
  EOS
end
