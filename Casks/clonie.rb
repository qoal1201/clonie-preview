cask "clonie" do
  version "20260910-clonie1"
  sha256 "99cdaaeb78d9b5c888b5823b91a0f35c703a3e401273d743eaa6213ece5eea47"

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
