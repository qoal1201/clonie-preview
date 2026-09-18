cask "clonie" do
  version "20260919-clonie1"
  sha256 "735bf90ca99fe748f69b35cdeab099bb1873696840bac4713e55fcf1ab0dec14"

  url "https://github.com/qoal1201/clonie-preview/releases/download/preview-#{version}/Clonie-1.0.6-arm64-notarized.zip"
  name "Clonie"
  desc "Local Markdown workspace with on-device context search"
  homepage "https://github.com/qoal1201/clonie-preview"

  livecheck do
    skip "Preview builds are updated manually"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Clonie.app"

  caveats <<~EOS
    This release is Developer ID signed and notarized by Apple.
    macOS first-launch confirmation and audio permissions still require your approval.
  EOS
end
