# Kanpe

A macOS menu-bar app that shows the keyboard shortcuts for whatever you're using, **including the website in your browser's current tab**.

The name comes from カンペ (*kanpe*), Japanese TV slang for the cue cards held up off camera.

Press `⌘` twice and keep holding (or, if you prefer, just hold `⌘`; choose under menu-bar icon → **Trigger**) and a panel appears with:

1. **Site shortcuts** for the active tab (GitHub, Gmail, YouTube… or any site you add), highlighted at the top.
2. **App shortcuts** read live from the frontmost app's menu bar.

In browsers the app's own menu shortcuts (File, Edit, View…) start **hidden**, because they're the same on every site, so the panel shows just the site's shortcuts. Click **Menus** in the panel header to show or hide them; the choice is remembered per app. Other apps show their menu shortcuts by default.

Release `⌘` (or press any key) to dismiss it. Shortcuts you type with `⌘` (⌘C, ⌘Tab, ⌘-click…) never trigger it.

## Install with Homebrew

```sh
brew tap viclzhu/kanpe https://github.com/viclzhu/Kanpe
brew install --cask viclzhu/kanpe/kanpe
```

Then open **Kanpe** from Applications. It lives in the menu bar and has no Dock icon.

> [!IMPORTANT]
> **The first launch is blocked by macOS.** You'll see *"Apple could not verify "Kanpe" is free of malware that may harm your Mac or compromise your privacy."* This happens because Kanpe isn't signed with a paid Apple Developer ID yet. It doesn't mean anything was found in the app. To allow it:
>
> 1. Click **Done** in the warning. Don't click **Move to Trash**.
> 2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
> 3. Next to *"Kanpe" was blocked to protect your Mac*, click **Open Anyway**.
> 4. Enter your password, then click **Open Anyway** again in the next warning.
>
> You do this once per version, so again after each `brew upgrade`. Homebrew prints these steps after it installs Kanpe.
>
> If you'd rather skip the dialog, you can remove the download quarantine flag instead. This tells macOS to trust the app without checking it:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/Kanpe.app
> ```

**Accessibility permission.** On first launch, turn Kanpe on in **System Settings → Privacy & Security → Accessibility**. Kanpe needs it to see the ⌘ trigger, read the app's menus and read the browser tab's address. Every release is signed with the same certificate, so this permission carries over when you upgrade.

**Updating and removing:**

```sh
brew update && brew upgrade --cask kanpe
brew uninstall --cask kanpe          # add --zap to also delete your site shortcuts and settings
```

Run `brew update` first so Homebrew sees a new version. It refreshes taps on its own only now and then (at most once a day), and `brew fetch` and `brew info` never do, so they can keep showing the old version.

Why the `brew tap` line: the repo isn't named `homebrew-…`, so Homebrew needs its URL once. Installing with the full name `viclzhu/kanpe/kanpe` also tells Homebrew to trust this one cask; it doesn't trust everything else in the repo.

## Build & run

Requires macOS 13+ and Swift 5.10+ (Command Line Tools are enough; Xcode is not required).

```sh
scripts/setup-signing.sh   # once: creates a local signing identity (see below)
scripts/bundle.sh          # → build/Kanpe.app
open build/Kanpe.app
```

On first launch, grant **Accessibility** access (System Settings → Privacy & Security → Accessibility). Until you do, the menu-bar icon shows ⚠︎ and ⌘ isn't detected, because macOS gives key events only to apps that have this access.

**Why `setup-signing.sh`:** macOS ties the Accessibility grant to the app's code signature. Ad-hoc builds get a new identity on every rebuild, so the grant stops applying even though the switch still looks on. The script creates a self-signed "Kanpe Local Signing" certificate in your login keychain, and `bundle.sh` uses it automatically, so the grant survives rebuilds. To remove the certificate: `security delete-identity -c "Kanpe Local Signing" ~/Library/Keychains/login.keychain-db`.

**Trigger not working?** Check the logs:

```sh
/usr/bin/log stream --predicate 'subsystem == "dev.victorzhu.Kanpe"' --level debug
```

`Launched; accessibility trusted: false` means permission is the problem. Remove Kanpe from the Accessibility list with −, then add it again.

Checks for the core logic: `swift build && .build/debug/KanpeSelfTest`

Debug without the UI (run from a terminal that has Accessibility access):

```sh
.build/debug/Kanpe --dump com.google.Chrome                 # print what the panel would show
.build/debug/Kanpe --render com.google.Chrome out.png https://github.com --level extended   # render to a PNG
                                                             #   --app-level sets the menus' level
                                                             #   also: --hide-menus, --all-pages
.build/debug/Kanpe --render-editor editor.png GitHub        # editor screenshot (needs Screen Recording)
```

## Editing shortcuts

Open the editor from the menu-bar icon → **Edit Shortcuts…** (⌘,), or click the ✎ button in the panel header to jump straight to the site you're on. The button shows **+** if that site has no shortcuts yet.

- **Sites** are listed in the sidebar. Use **+** / **−** to add or delete one, and right-click a site to **Duplicate**, **Revert to Built-in** or **Show in Finder**. **•••** → **Restore Built-in Sites** brings back built-in sites you deleted.
- **Domains** appear as chips. Type a domain and press Return to add it. Subdomains are included, and you can narrow a domain with a path.
- **Shortcuts:** each row has a description, a keys field and a level.
  - Type keys in the notation described below, or click ◉ and press them. A combination like ⇧⌘P works, and so does a sequence like G then I; recording stops after a short pause.
  - Keycaps preview live as you type.
  - Drag rows to reorder them, and click the colored pill to set the level.
- **Groups:** rename one by clicking its title. Its **•••** menu sets the level for all its shortcuts, moves the group up or down, or deletes it.
- **Pages:** under the domains, **Add Page** names a part of the site and the URL paths that belong to it (see [Pages](#pages-shortcuts-for-the-part-of-the-site-youre-on)). Type a full URL into the path field and it's turned into a path. **Try a URL** shows which page a URL is on. Once a site has pages, each group header has a page chip: pick the pages the group belongs to, or **All pages**.

Kanpe stays menu-bar only, with no Dock icon, even while the editor is open. To get back to the editor, use the menu-bar icon → **Edit Shortcuts…** again. If you'd rather have a Dock icon and ⌘Tab while editing, turn on **Show Dock Icon While Editing** in the menu-bar menu. ⌘C/⌘V/⌘X/⌘Z/⌘A and ⌘W work in the editor either way.

Changes save automatically and show in the panel right away. A site you've edited won't be overwritten by app updates.

## Site shortcut files

Site packs are JSON files in `~/Library/Application Support/Kanpe/Sites/`. Use the menu-bar icon → **Open Site Shortcuts Folder**, then **Reload Site Shortcuts** after you edit. Bundled packs are copied there on first launch. Edit them freely: the app never overwrites a pack you've changed.

```json
{
  "name": "GitHub",
  "match": ["github.com"],
  "groups": [
    {
      "title": "Repository",
      "shortcuts": [
        { "title": "Go to Issues", "keys": "g i" },
        { "title": "Command palette", "keys": "cmd+k" },
        { "title": "Back / forward 5 s", "keys": "left or right" }
      ]
    }
  ]
}
```

### Detail levels: Core, Extended, Complete

Each site can be shown at one of three levels, and each level includes the ones before it:
- **Core:** the handful you'd put on a sticky note. This is what a site shows until you pick another level.
- **Extended:** everyday shortcuts.
- **Complete:** everything in the pack.

The level is remembered **per site**. Change it from the **Core | Extended | Complete** control in the panel header (keep holding `⌘` and click it), or from the menu-bar icon → **Detail Level**.

Tag shortcuts in a pack with `"level": "core" | "extended" | "complete"`. You can put a `level` on a group, which applies to all its shortcuts, and override it on individual shortcuts. Untagged shortcuts count as Core, so a pack without any levels always shows everything and doesn't get a level picker.

```json
{ "title": "Notifications", "level": "complete", "shortcuts": [
    { "title": "Mark as done", "keys": "e" },
    { "title": "Go to notifications", "keys": "g n", "level": "extended" } ] }
```

**App menu shortcuts have levels too.** A second **Core | Extended | Complete** control sits next to **Menus**, and is remembered **per app**. Menus don't say which items matter, so Kanpe sorts them like this:
- **Core:** universal chords (⌘C, ⌘V, ⌘Z, ⇧⌘Z, ⌘X, ⌘A, ⌘F, ⌘S, ⌘N, ⌘W, ⌘Q, ⌘,) in any app or language, plus well-known commands such as New Tab, Reopen Closed Tab, Open Location, Back/Forward, Reload and Select Next/Previous Tab.
- **Extended:** other ⌘ shortcuts with at most one extra modifier (⇧⌘ or ⌥⌘) and at most one submenu deep, e.g. Developer › Developer Tools.
- **Complete:** everything else: three-modifier chords, shortcuts without ⌘ (such as ⌃ window tiling and fn keys), and items in deeper submenus.

Apps start at **Core**, like sites. For Chrome that's 22 shortcuts at Core, 59 at Extended and all 80 at Complete. When a site's picker and the menus' picker are both showing, the site's picker is labelled with the site name.

### Pages: shortcuts for the part of the site you're on

A site can be split into pages by URL path, and a group can be limited to some of them. On GitHub, a repo's code view shows **Code** shortcuts, an issue shows **Issues & PRs** shortcuts, a pull request also shows **PR changes**, and so on. Groups not limited to a page (like GitHub's **Site-wide**) show everywhere on the site. Page-specific groups come first in the panel, and the page name shows next to the host: `github.com › Issue`. With only one site matching, group titles drop the site name (the header already shows it).

**Turning it off:** the target button (◎) next to the level picker in the panel header switches a site between "only what fits this page" and "every shortcut on every page". It's remembered per site, and on by default. You can also toggle it from the menu-bar icon → **Match Shortcuts to Page**.

```json
{
  "name": "GitHub",
  "match": ["github.com"],
  "pages": [
    { "name": "Repository", "paths": ["/*/*/**", "!/{settings,orgs,notifications}/**"] },
    { "name": "Issues", "paths": ["/*/*/issues", "/issues"] },
    { "name": "Issue", "paths": ["/*/*/issues/*"] }
  ],
  "groups": [
    { "title": "Site-wide", "shortcuts": [ { "title": "Focus search", "keys": "/" } ] },
    { "title": "Repository", "pages": ["Repository"], "shortcuts": [ { "title": "Go to Issues", "keys": "g i" } ] },
    { "title": "Issues & PRs", "pages": ["Issue"], "shortcuts": [ { "title": "Set labels", "keys": "l" } ] }
  ]
}
```

Path patterns match whole path segments, ignore case, a trailing slash and the query string:
- `*` is exactly one segment: `/*/*` is `/owner/repo`.
- `**` is any number of segments, including none: `/*/*/issues/**` is the issue list and every page under it.
- `*` inside a segment is a wildcard: `/*/*/pull*` matches `pull` and `pulls`.
- `{a,b}` is either: `/{issues,pulls}`.
- `!` at the start excludes: a page matches if any of its patterns match and none of its `!` patterns do.

A URL can be on several pages at once (a repo's issue is on both **Repository** and **Issue**). List pages from general to specific; the panel header shows the last one that matches.

**Updates to bundled packs:** when a new version of the app includes an updated pack, it replaces your copy only if you haven't edited it. Packs you've edited are never overwritten.

**`match`** takes hosts. Subdomains also match, so `github.com` matches `gist.github.com`, and a leading `www.` is ignored. You can add a path prefix (`google.com/maps`) or a wildcard (`*.atlassian.net`).

**`keys` notation:**
- Separate chords with spaces for a sequence: `g i` means "G then I".
- Join keys with `+` for a chord: `shift+cmd+p`.
- Write ` or ` between alternatives.
- Modifiers: `cmd`, `shift`, `opt`/`alt`, `ctrl`.
- Named keys: `enter`, `esc`, `tab`, `space`, `delete`, `up`/`down`/`left`/`right`, `home`, `end`, `pageup`, `pagedown`, `f1`…`f20`, `plus`.

## How the tab URL is read

The URL is read only when you open the panel, and only from the frontmost app if it's a known browser. It's used in memory to pick site packs, and it is never stored, logged or sent anywhere.

1. **Accessibility (primary).** Kanpe looks for the page's `AXWebArea` and reads its `AXURL`. For Chromium-based browsers it first sets `AXManualAccessibility`, which tells the browser to expose its web content to Accessibility. This works for Safari, Chrome, Edge, Brave, Arc, Vivaldi and Opera, and needs no extra permission.
2. **AppleScript (fallback, can be turned off in the menu).** This asks the browser for the URL of its active tab. macOS shows an Automation prompt once per browser.

Firefox only works through Accessibility, and how reliable that is depends on the Firefox version.

## Releasing

1. Set the fallback `VERSION` in `scripts/bundle.sh` to the new version, then build the zip: `VERSION=0.3.0 scripts/release.sh`. It prints the zip's sha256. Build on the Mac that has "Kanpe Local Signing", so users keep their Accessibility permission (`codesign -dvv build/Kanpe.app` should show `Authority=Kanpe Local Signing`).
2. Publish it **first**: `gh release create v0.3.0 build/Kanpe-0.3.0.zip --target main --title "Kanpe 0.3.0" --notes "…"`. In the notes, give the upgrade command as `brew update && brew upgrade --cask kanpe`.
3. Then, in `Casks/kanpe.rb`, set `version` and `sha256`, commit and push. Pushing the cask before the zip exists would give anyone who updates in between a download error.
4. Check it: `brew update && brew fetch --cask viclzhu/kanpe/kanpe`. This downloads the zip and verifies the sha256.

Upload the same zip you took the sha256 from. Every build gets a new signature timestamp, so a rebuilt zip has a different checksum.

## Layout

```
Sources/KanpeCore     pure logic: models, key notation, site matching, pack loading, column layout, trigger gesture
Sources/Kanpe         app: activation (event monitors → trigger state machine), Accessibility menu + URL reading, panel UI, menu-bar item
Sources/KanpeSelfTest assertion checks for KanpeCore
Resources/Sites         bundled site packs
scripts/bundle.sh       builds and signs Kanpe.app
scripts/release.sh      zips a signed build for GitHub Releases and prints its sha256
Casks/kanpe.rb          Homebrew cask (this repo doubles as a tap)
scripts/make-icon.swift draws Resources/AppIcon.icns (カンペ on a cue card)
```
