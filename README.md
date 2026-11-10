# Kanpe

A macOS menu-bar app that shows the keyboard shortcuts for whatever you're using, **including the website in your browser's current tab**.

The name comes from カンペ (*kanpe*), Japanese TV slang for the cue cards held up off camera.

Press `⌘` twice and keep holding (or, if you prefer, just hold `⌘`; choose under menu-bar icon → **Trigger**) and a panel appears with:

1. **Site shortcuts** for the active tab (GitHub, Gmail, YouTube… or any site you add), highlighted at the top.
2. **App shortcuts** read live from the frontmost app's menu bar.

Release `⌘` (or press any key) to dismiss it. Shortcuts you type with `⌘` (⌘C, ⌘Tab, ⌘-click…) never trigger it.

## Build & run

Requires macOS 13+ and Swift 5.10+ (Command Line Tools are enough; Xcode is not required).

```sh
scripts/bundle.sh          # → build/Kanpe.app (ad-hoc signed)
open build/Kanpe.app
```

On first launch, grant **Accessibility** access (System Settings → Privacy & Security → Accessibility).
With ad-hoc signing, each rebuild counts as a new app to macOS: if the panel stops appearing, remove Kanpe from the Accessibility list and add it again. Signing with a stable identity (`SIGN_IDENTITY="…" scripts/bundle.sh`) avoids this.

Checks for the core logic: `swift build && .build/debug/KanpeSelfTest`

Debug without the UI (run from a terminal that has Accessibility access):

```sh
.build/debug/Kanpe --dump com.google.Chrome                 # print what the panel would show
.build/debug/Kanpe --render com.google.Chrome out.png https://github.com --level extended   # render to a PNG
```

## Adding site shortcuts

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

## Layout

```
Sources/KanpeCore     pure logic: models, key notation, site matching, pack loading, column layout, trigger gesture
Sources/Kanpe         app: activation (event monitors → trigger state machine), Accessibility menu + URL reading, panel UI, menu-bar item
Sources/KanpeSelfTest assertion checks for KanpeCore
Resources/Sites         bundled site packs
scripts/bundle.sh       builds and signs Kanpe.app
```
