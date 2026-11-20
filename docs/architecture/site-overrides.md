# How your changes to built-in sites are stored and merged

Kanpe ships some site packs in the app: GitHub, Gmail, YouTube and Figma. You can change these
built-in packs in the editor, and a new version of Kanpe can change them too. Kanpe never copies
a built-in pack into your folder. It stores only your changes, in `<site>.edits.json`, and
applies them to the current built-in pack each time it loads. So each app update arrives, and
your changes stay on top of it.

Code: `Sources/KanpeCore/Overrides.swift` (`SiteOverrides`) and
`Sources/KanpeCore/SitePacks.swift` (`SitePackStore`).

## Components and files

```mermaid
flowchart LR
    subgraph Bundle["Kanpe.app/Contents/Resources (read-only)"]
        Sites["Sites/#lt;site#gt;.json<br/>built-in packs, every item has an id"]
        Legacy["LegacySites/#lt;site#gt;-#lt;digest#gt;.json<br/>earlier versions, only for migration"]
    end

    subgraph User["~/Library/Application Support/Kanpe/Sites"]
        Edits["#lt;site#gt;.edits.json<br/>your changes to a built-in pack"]
        Own["#lt;name#gt;.json<br/>your own packs and forks"]
        Backups["Backups/#lt;site#gt;.json<br/>old full copies kept after migration"]
        Manifest[".installed.json<br/>0.2.1 manifest, removed after migration"]
    end

    subgraph Core["KanpeCore"]
        Store["SitePackStore<br/>load · save · delete · revert · restore · migrate"]
        Overrides["SiteOverrides<br/>diff(base:edited:) · apply(to:)"]
        Keyed["Keyed<br/>gives every item a key (its id, or one made from its titles)"]
    end

    subgraph App["Kanpe app"]
        Delegate["AppDelegate<br/>reloadPacks()"]
        Panel["PanelView<br/>shortcuts and the 'updated' hover text"]
        Editor["EditorModel / EditorViews<br/>edits the whole merged pack"]
    end

    Sites --> Store
    Legacy --> Store
    Edits <--> Store
    Own <--> Store
    Manifest --> Store
    Store --> Backups
    Store <--> Overrides
    Overrides --> Keyed
    Delegate --> Store
    Delegate --> Panel
    Editor <--> Store
```

## Loading

`SitePackStore.load()` builds the list of packs that the panel and the editor use.

```mermaid
flowchart TD
    Start(["load()"]) --> UserFiles["Read each #lt;name#gt;.json in your folder<br/>(not .edits.json files)"]
    UserFiles --> UserPack["LoadedPack: your own pack"]
    UserFiles --> Each["For each built-in Sites/#lt;site#gt;.json"]
    Each --> Shadow{"Do you have a<br/>#lt;site#gt;.json with the same name?"}
    Shadow -- yes --> Skip1["Skip it: your file is a fork and replaces it"]
    Shadow -- no --> Read["Read #lt;site#gt;.edits.json, if there is one"]
    Read --> Del{"deleted: true?"}
    Del -- yes --> Skip2["Skip it: you deleted this site"]
    Del -- no --> Apply["overrides.apply(to: built-in pack)"]
    Apply --> Built["LoadedPack: isBuiltIn<br/>isCustomized = the edits file is not empty<br/>unapplied = changes that no longer apply"]
    UserPack --> Sort(["Sort by file name"])
    Built --> Sort
```

## Saving from the editor

The editor works on the merged pack and never sees the edits file. On save, the store works out
what now differs from the built-in pack and rewrites the whole edits file.

```mermaid
sequenceDiagram
    participant E as EditorModel
    participant S as SitePackStore
    participant O as SiteOverrides
    participant F as Sites folder

    E->>S: save(mergedPack, to: url)
    alt url is a built-in pack
        S->>S: decode the built-in pack from the app
        S->>O: diff(base: built-in, edited: mergedPack)
        O-->>S: overrides (only what differs)
        S->>S: keep the "deleted" flag from the old edits file
        alt overrides are empty
            S->>F: remove #lt;site#gt;.edits.json
        else
            S->>F: write #lt;site#gt;.edits.json
        end
    else your own pack
        S->>F: write the whole #lt;name#gt;.json
    end
```

Other operations on a built-in pack also change only its edits file:

| Operation | What happens to `<site>.edits.json` |
|---|---|
| `delete` | sets `deleted: true` and keeps your changes |
| `restoreDeletedBuiltIns` | removes `deleted`, so the site comes back with your changes |
| `revertToBuiltIn` | removes the file |

## Diff and apply

```mermaid
flowchart TB
    subgraph Diff["diff(base:edited:)"]
        direction TB
        D1["Give every item a key in both packs (Keyed)"] --> D2["Compare each item by key"]
        D2 --> D3["Only in base: deleted: true"]
        D2 --> D4["Only in edited: added: true, with every field"]
        D2 --> D5["In both: only the fields that differ<br/>(title, keys, level, paths…)"]
        D2 --> D6["A longest increasing subsequence finds the items that kept their order;<br/>each other item gets after: X or first: true"]
        D2 --> D7["Shortcut in a different group: group: id"]
    end

    subgraph Apply["apply(to:)"]
        direction TB
        A1["Give the current built-in pack keys (Keyed)"] --> A2["Remove the items marked deleted"]
        A2 --> A3["Change the stored fields of each item<br/>(your value wins)"]
        A3 --> A4["Insert added and moved items<br/>after their anchor, or first"]
        A4 --> A5["Changes to items the built-in pack no longer has → unapplied"]
        A5 --> A6["updated = the later of your date and the built-in pack's date"]
    end

    Diff -- "#lt;site#gt;.edits.json" --> Apply
```

How the merge works:

- **Keys.** An item's key is its `id`, which stays the same when the item is renamed or moved.
  An item without an id gets a key made from its titles, such as `p:name`, `g:title` or
  `s:group/title`. A `#2` suffix makes a key unique within its kind.
- **One field at a time.** If you change a shortcut's keys and an update fixes its title, you
  get both changes.
- **Lists are replaced whole.** These are `match`, a page's `paths` and a group's `pages`.
- **Relative positions.** A new built-in item that your changes don't mention keeps its place
  in the built-in order. Your added and moved items go after their anchor.
- **Conflicts.** If you and an update change the same field, your value wins.
- **Items an update removed.** Changes to them are listed in `unapplied` and shown in the
  editor. The next save drops them.
- **Levels.** `"level": "inherit"` clears a level, so the shortcut takes its group's level.

Example `github.edits.json`:

```json
{
  "updated": "2026-11-10",
  "shortcuts": {
    "code.open-blame":   { "level": "inherit" },
    "code.jump-to-line": { "level": "inherit" }
  }
}
```

## Migrating from 0.2.1 full copies

Kanpe 0.2.1 copied each built-in pack into your folder and recorded a digest of each copy in
`.installed.json`. On the first launch of the new version, `migrateLegacyCopies` turns those
copies into edits files. Because it removes the manifest at the end, it runs only once.

```mermaid
flowchart TD
    M(["migrateLegacyCopies()"]) --> HasManifest{".installed.json exists?"}
    HasManifest -- no --> Done(["Nothing to do"])
    HasManifest -- yes --> Loop["For each built-in pack listed in the manifest"]
    Loop --> Exists{"Is your copy still there?"}
    Exists -- no --> MarkDel["delete(): you had deleted it"]
    Exists -- yes --> Same{"Does its digest match the<br/>installed or the current version?"}
    Same -- yes --> Remove["Remove the copy: it was not edited"]
    Same -- no --> Cands["Possible starting versions:<br/>the current pack and each LegacySites version"]
    Cands --> Pick["Diff your copy against each one.<br/>Use the diff with the fewest changes;<br/>on a tie, use the manifest's version"]
    Pick --> Backup["Move your copy to Backups/"]
    Backup --> Write["Write #lt;site#gt;.edits.json"]
    MarkDel --> Next
    Remove --> Next
    Write --> Next["Next pack"]
    Next --> Loop
    Next --> Rm(["Remove .installed.json"])
```

The closest version is used, not simply the one the manifest names, because a copy can be
changed by hand without the manifest being updated. If the manifest's version were always used,
those hand-made changes would be stored as your edits.
