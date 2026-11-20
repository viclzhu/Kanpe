import Foundation
import Combine
import KanpeCore

/// State for the shortcut editor. Edits are saved automatically shortly after they happen.
@MainActor
final class EditorModel: ObservableObject {
    @Published var sites: [EditableSite] = []
    @Published var selection: EditableSite.ID?
    @Published var unreadableFiles: [String] = []
    @Published var saveError: String?
    /// Built-in sites the user has changed.
    @Published private(set) var customized: Set<EditableSite.ID> = []
    /// Built-in sites with changes that no longer apply to the current built-in pack.
    @Published private(set) var unapplied: [EditableSite.ID: [String]] = [:]

    let store: SitePackStore
    /// Called after anything is written, so the panel picks up changes immediately.
    var onChange: () -> Void = {}

    private var pendingSaves: [EditableSite.ID: DispatchWorkItem] = [:]

    init(store: SitePackStore) {
        self.store = store
        reload()
    }

    func reload() {
        flushSaves()
        let result = store.load()
        var customized: Set<EditableSite.ID> = []
        var unapplied: [EditableSite.ID: [String]] = [:]
        sites = result.loaded
            .map { loaded in
                let site = EditableSite(loaded.pack, fileURL: loaded.fileURL)
                if loaded.isCustomized { customized.insert(site.id) }
                if !loaded.unapplied.isEmpty { unapplied[site.id] = loaded.unapplied }
                return site
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        self.customized = customized
        self.unapplied = unapplied
        unreadableFiles = result.errors.map(\.file)
        if selection == nil || !sites.contains(where: { $0.id == selection }) {
            selection = sites.first?.id
        }
    }

    func binding(for id: EditableSite.ID) -> EditableSite? {
        sites.first { $0.id == id }
    }

    /// Called by the detail view on every edit.
    func update(_ site: EditableSite) {
        guard let index = sites.firstIndex(where: { $0.id == site.id }), sites[index] != site else { return }
        var site = site
        site.updated = PackDate.string(from: Date())
        sites[index] = site
        scheduleSave(site.id)
    }

    // MARK: Sites

    func addSite() {
        var site = EditableSite.blank()
        site.updated = PackDate.string(from: Date())
        site.fileURL = store.newFileURL(forName: site.name)
        sites.append(site)
        selection = site.id
        save(site.id)
    }

    func duplicate(_ id: EditableSite.ID) {
        guard var copy = binding(for: id) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        copy.updated = PackDate.string(from: Date())
        copy.fileURL = store.newFileURL(forName: copy.name)
        sites.append(copy)
        selection = copy.id
        save(copy.id)
    }

    func delete(_ id: EditableSite.ID) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        pendingSaves.removeValue(forKey: id)?.cancel()
        if let url = sites[index].fileURL {
            do { try store.delete(url) } catch { saveError = error.localizedDescription }
        }
        sites.remove(at: index)
        if selection == id {
            selection = sites.isEmpty ? nil : sites[min(index, sites.count - 1)].id
        }
        onChange()
    }

    func isBuiltIn(_ site: EditableSite) -> Bool {
        site.fileURL.map(store.isBuiltIn) ?? false
    }

    /// The file to reveal in Finder: the user's changes for a built-in site (nil if there are none).
    func fileToReveal(_ site: EditableSite) -> URL? {
        guard let url = site.fileURL else { return nil }
        guard store.isBuiltIn(url) else { return url }
        let edits = store.editsURL(for: url)
        return FileManager.default.fileExists(atPath: edits.path) ? edits : nil
    }

    func revertToBuiltIn(_ id: EditableSite.ID) {
        guard let index = sites.firstIndex(where: { $0.id == id }), let url = sites[index].fileURL else { return }
        pendingSaves.removeValue(forKey: id)?.cancel()
        do {
            try store.revertToBuiltIn(url)
            if let pack = store.load().loaded.first(where: { $0.fileURL == url })?.pack {
                var fresh = EditableSite(pack, fileURL: url)
                fresh.id = id
                sites[index] = fresh
            }
            customized.remove(id)
            unapplied[id] = nil
            onChange()
        } catch {
            saveError = error.localizedDescription
        }
    }

    var hasDeletedBuiltIns: Bool { !store.deletedBuiltIns().isEmpty }

    func restoreBuiltIns() {
        do {
            try store.restoreDeletedBuiltIns()
            reload()
            onChange()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Saving

    private func scheduleSave(_ id: EditableSite.ID) {
        pendingSaves[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save(id) }
        pendingSaves[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save(_ id: EditableSite.ID) {
        pendingSaves[id] = nil
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        let site = sites[index]
        let url = site.fileURL ?? store.newFileURL(forName: site.name)
        do {
            try store.save(site.pack, to: url)
            sites[index].fileURL = url
            if store.isBuiltIn(url) {
                // Saving rewrites the changes from scratch, so ones that no longer applied are gone.
                unapplied[id] = nil
                if (try? store.readOverrides(for: url))??.isEmpty == false { customized.insert(id) } else { customized.remove(id) }
            }
            saveError = nil
            onChange()
        } catch {
            saveError = "Couldn't save \(site.name): \(error.localizedDescription)"
        }
    }

    /// Writes anything still waiting (e.g. when the window closes).
    func flushSaves() {
        for (id, work) in pendingSaves {
            work.cancel()
            save(id)
        }
    }
}
