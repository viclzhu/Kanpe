cask "kanpe" do
  version "0.2.0"
  sha256 "1abc1c5e21da2e58640d10b797039cc8f80a4fc71d13c160db5e9874f71d30f1"

  url "https://github.com/viclzhu/Kanpe/releases/download/v#{version}/Kanpe-#{version}.zip"
  name "Kanpe"
  desc "Menu bar cheat sheet for app and website keyboard shortcuts"
  homepage "https://github.com/viclzhu/Kanpe"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "Kanpe.app"

  uninstall quit: "dev.victorzhu.Kanpe"

  zap trash: [
    "~/Library/Application Support/Kanpe",
    "~/Library/Preferences/dev.victorzhu.Kanpe.plist",
  ]

  caveats <<~EOS
    Kanpe isn't signed with an Apple Developer ID, so macOS blocks its first launch with
    "Apple could not verify "Kanpe" is free of malware…". To allow it:
      1. Open Kanpe, then click Done in the warning. Don't click Move to Trash.
      2. Open System Settings → Privacy & Security, scroll down to Security,
         and click Open Anyway next to "Kanpe" was blocked.
      3. Enter your password, then click Open Anyway again.
    You do this once per version, so again after each upgrade.

    Kanpe also needs Accessibility access to read menu shortcuts and the browser tab's URL.
    After first launch, turn it on in System Settings → Privacy & Security → Accessibility.
  EOS
end
