import AppKit
import ApplicationServices

/// Reads the URL of the active tab in the frontmost browser.
///
/// Privacy: this runs only at the moment the panel is opened, for the frontmost app.
/// The URL is used in memory to pick site packs and is never stored or logged.
enum BrowserURLReader {
    enum Engine { case safari, chromium, firefox }

    static let browsers: [String: Engine] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.beta": .chromium,
        "com.google.Chrome.canary": .chromium,
        "org.chromium.Chromium": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
        "company.thebrowser.Browser": .chromium, // Arc
        "org.mozilla.firefox": .firefox,
        "org.mozilla.firefoxdeveloperedition": .firefox,
    ]

    static func isBrowser(_ bundleID: String?) -> Bool {
        bundleID.map { browsers[$0] != nil } ?? false
    }

    /// Accessibility first (no extra permission needed beyond what the app already has).
    /// Off the main thread is fine.
    static func urlViaAccessibility(pid: pid_t, bundleID: String) -> URL? {
        guard let engine = browsers[bundleID] else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)

        if engine == .chromium {
            // Chromium only builds its web accessibility tree when asked. This flag is the
            // lightweight opt-in (unlike AXEnhancedUserInterface, it doesn't affect window animations).
            AX.set(app, "AXManualAccessibility", kCFBooleanTrue)
        }

        guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.element(app, kAXMainWindowAttribute) else {
            return nil
        }
        if let url = findWebAreaURL(in: window) { return url }

        // Firefox and some builds expose the page URL as the window's document.
        if let doc = AX.string(window, kAXDocumentAttribute), let url = URL(string: doc), url.host != nil {
            return url
        }
        return nil
    }

    /// Breadth-first search for the first AXWebArea that has an AXURL. The top-level page
    /// is found before any nested iframes.
    private static func findWebAreaURL(in root: AXUIElement) -> URL? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 1500 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let v = AX.values(element, [kAXRoleAttribute as String, kAXURLAttribute as String, kAXChildrenAttribute as String])
            if (v[0] as? String) == "AXWebArea", let url = asURL(v[1]) {
                return url
            }
            if depth < 30, let children = v[2] as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return nil
    }

    private static func asURL(_ value: CFTypeRef?) -> URL? {
        if let url = value as? URL, url.host != nil { return url }
        if let s = value as? String, let url = URL(string: s), url.host != nil { return url }
        return nil
    }

    /// AppleScript fallback for Safari and Chromium browsers. The first use triggers the macOS
    /// "Kanpe wants to control <Browser>" Automation prompt. Must run on the main thread.
    static func urlViaAppleScript(bundleID: String) -> URL? {
        guard let engine = browsers[bundleID], engine != .firefox else { return nil }
        let expression = engine == .safari ? "URL of front document" : "URL of active tab of front window"
        let source = "tell application id \"\(bundleID)\" to return \(expression)"
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return nil }
        return URL(string: result)
    }
}
