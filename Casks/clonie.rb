cask "clonie" do
  version "20260910-logo1"
  sha256 "586d72e93d9e2f62a312a0ff9589ca4a0020e55b41bc910f6cf13d5da3ef741d"

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
