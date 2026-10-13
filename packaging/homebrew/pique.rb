# Template for Casks/pique.rb in github.com/loicbisiere/homebrew-tap.
# The release workflow (.github/workflows/build.yml) fills in @VERSION@ and @SHA256@ and pushes it to the tap.
cask "pique" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/loicbisiere/pique/releases/download/v#{version}/Pique-#{version}.zip"
  name "Pique"
  desc "Menu bar camera and print status for Bambu Lab 3D printers"
  homepage "https://github.com/loicbisiere/pique"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Pique.app"

  uninstall quit: "com.loicbisiere.Pique"

  zap trash: "~/Library/Preferences/com.loicbisiere.Pique.plist"

  caveats <<~EOS
    Pique is not notarized by Apple yet, so macOS blocks its first launch.
    Open it once, then go to System Settings > Privacy & Security and click "Open Anyway".
  EOS
end
