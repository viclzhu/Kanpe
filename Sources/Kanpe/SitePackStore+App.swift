import Foundation
import KanpeCore

extension SitePackStore {
    /// The user's Sites folder plus the packs bundled with the app.
    static var app: SitePackStore {
        SitePackStore(directory: defaultDirectory, bundledDirectory: Bundle.main.resourceURL?.appendingPathComponent("Sites"))
    }

    /// Earlier versions of the bundled packs, for converting edited copies (see `migrateLegacyCopies`).
    static var legacyDirectory: URL? { Bundle.main.resourceURL?.appendingPathComponent("LegacySites") }
}
