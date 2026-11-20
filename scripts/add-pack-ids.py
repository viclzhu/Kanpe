#!/usr/bin/env python3
"""Adds missing "id"s to site packs, keeping the file's formatting.

    python3 scripts/add-pack-ids.py Resources/Sites/*.json

Ids are what the user's changes to a built-in pack refer to (see SiteOverrides), so once a pack
has shipped, keep each id when you rename or move its page, group or shortcut. New ones get
slugs: "code" for a group, "code.open-blame" for a shortcut in it, "pull-requests" for a page.
Expects each object's "title" (or a page's "name") to be its first key.
"""
import json, re, sys

def slug(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return s or "item"

def add_ids(path):
    text = open(path).read()
    pack = json.loads(text)
    # Ids are unique per kind: a page and a group may share one.
    used = {"page": set(), "group": set(), "shortcut": set()}
    for p in pack.get("pages") or []:
        used["page"].add(p.get("id"))
    for g in pack["groups"]:
        used["group"].add(g.get("id"))
        for s in g["shortcuts"]:
            used["shortcut"].add(s.get("id"))

    def unique(kind, base):
        candidate, n = base, 2
        while candidate in used[kind]:
            candidate, n = f"{base}-{n}", n + 1
        used[kind].add(candidate)
        return candidate

    # Ids in document order for every "name" (after the pack's own) and "title" occurrence;
    # None where the object already has one.
    names = [None]  # the pack's own "name"
    for p in pack.get("pages") or []:
        names.append(None if "id" in p else unique("page", slug(p["name"])))
    titles = []
    for g in pack["groups"]:
        gid = g.get("id") or unique("group", slug(g["title"]))
        titles.append(None if "id" in g else gid)
        g["id"] = gid
        for s in g["shortcuts"]:
            titles.append(None if "id" in s else unique("shortcut", f"{gid}.{slug(s['title'])}"))

    queues = {"name": iter(names), "title": iter(titles)}
    def insert(m):
        new_id = next(queues[m.group(2)])
        if new_id is None:
            return m.group(0)
        prefix = m.group(1)
        if "\n" in prefix:  # key on its own line: add an "id" line with the same indent
            indent = prefix[prefix.rindex("\n"):]
            return f'{prefix}"id": "{new_id}",{indent}"{m.group(2)}": '
        return f'{prefix}"id": "{new_id}", "{m.group(2)}": '
    out = re.sub(r'(\{\s*)"(name|title)": ', insert, text)
    # The pack's own "name" follows the top-level "{" too, and was skipped by its None above.
    json.loads(out)  # still valid
    if out != text:
        open(path, "w").write(out)
        print(f"{path}: added ids")

for path in sys.argv[1:]:
    add_ids(path)
