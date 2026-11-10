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

    let store: SitePackStore
    let bundledDirectory: URL?
    /// Called after anything is written, so the panel picks up changes immediately.
    var onChange: () -> Void = {}

    private var pendingSaves: [EditableSite.ID: DispatchWorkItem] = [:]

    init(store: SitePackStore, bundledDirectory: URL?) {
        self.store = store
        self.bundledDirectory = bundledDirectory
        reload()
    }

    func reload() {
        flushSaves()
        let result = store.load()
        sites = result.loaded
            .map { EditableSite($0.pack, fileURL: $0.fileURL) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        sites[index] = site
        scheduleSave(site.id)
    }

    // MARK: Sites

    func addSite() {
        var site = EditableSite.blank()
        site.fileURL = store.newFileURL(forName: site.name)
        sites.append(site)
        selection = site.id
        save(site.id)
    }

    func duplicate(_ id: EditableSite.ID) {
        guard var copy = binding(for: id) else { return }
        copy.id = UUID()
        copy.name += " Copy"
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
        site.fileURL.flatMap { store.bundledPackURL(for: $0, in: bundledDirectory) } != nil
    }

    func revertToBuiltIn(_ id: EditableSite.ID) {
        guard let index = sites.firstIndex(where: { $0.id == id }), let url = sites[index].fileURL else { return }
        pendingSaves.removeValue(forKey: id)?.cancel()
        do {
            try store.revertToBundled(url, from: bundledDirectory)
            if let pack = store.load().loaded.first(where: { $0.fileURL == url })?.pack {
                var fresh = EditableSite(pack, fileURL: url)
                fresh.id = id
                sites[index] = fresh
            }
            onChange()
        } catch {
            saveError = error.localizedDescription
        }
    }

    var hasDeletedBuiltIns: Bool { !store.missingBundledPacks(in: bundledDirectory).isEmpty }

    func restoreBuiltIns() {
        do {
            try store.restoreMissingBundledPacks(from: bundledDirectory)
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
