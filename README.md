# Kanpe

A macOS menu-bar app that shows the keyboard shortcuts for whatever you're using, **including the website in your browser's current tab**.

The name comes from カンペ (*kanpe*), Japanese TV slang for the cue cards held up off camera.

Press `⌘` twice and keep holding (or, if you prefer, just hold `⌘`; choose under menu-bar icon → **Trigger**) and a panel appears with:

1. **Site shortcuts** for the active tab (GitHub, Gmail, YouTube… or any site you add), highlighted at the top.
2. **App shortcuts** read live from the frontmost app's menu bar.

In browsers the app's own menu shortcuts (File, Edit, View…) start **hidden**, because they're the same on every site, so the panel shows just the site's shortcuts. Click **Menus** in the panel header to show or hide them; the choice is remembered per app. Other apps show their menu shortcuts by default.

Release `⌘` (or press any key) to dismiss it. Shortcuts you type with `⌘` (⌘C, ⌘Tab, ⌘-click…) never trigger it.

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

### Pages: shortcuts for the part of the site you're on

A site can be split into pages by URL path, and a group can be limited to some of them. On GitHub, a repo's code view shows **Code** shortcuts, an issue shows **Issues & PRs** shortcuts, a pull request also shows **PR changes**, and so on. Groups not limited to a page (like GitHub's **Site-wide**) show everywhere on the site. Page-specific groups come first in the panel, and the page name shows next to the host: `github.com › Issue`.

**Turning it off:** the **This page / All pages** button in the panel header switches a site between "only what fits this page" and "every shortcut on every page". It's remembered per site, and on by default. You can also toggle it from the menu-bar icon → **Match Shortcuts to Page**.

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

## Layout

```
Sources/KanpeCore     pure logic: models, key notation, site matching, pack loading, column layout, trigger gesture
Sources/Kanpe         app: activation (event monitors → trigger state machine), Accessibility menu + URL reading, panel UI, menu-bar item
Sources/KanpeSelfTest assertion checks for KanpeCore
Resources/Sites         bundled site packs
scripts/bundle.sh       builds and signs Kanpe.app
scripts/make-icon.swift draws Resources/AppIcon.icns (カンペ on a cue card)
```
