cask "kanpe" do
  version "0.1.0"
  sha256 "a23045403fcdacd386b13070591075fd938e5372f0bc52f60cd04394cf6e886a"

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
    Kanpe needs Accessibility access to read menu shortcuts and the browser tab's URL.
    After first launch, turn it on in System Settings → Privacy & Security → Accessibility.
  EOS
end
