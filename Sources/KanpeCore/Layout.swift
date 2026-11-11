import Foundation

/// Arranges shortcut groups into newspaper-style columns.
///
/// Groups flow top-to-bottom, left-to-right in their original order. Long groups may continue in
/// the next column (the continuation gets `part > 0`), so one huge menu doesn't leave a ragged
/// gap. The number of columns is chosen so the panel's shape is close to the screen's.
public enum ColumnLayout {
    /// Size estimates, in points, used to compare candidate layouts. The real panel is measured
    /// afterwards; these only need to be roughly right.
    public struct Metrics: Sendable {
        public var columnWidth: Double
        public var columnSpacing: Double
        public var rowHeight: Double
        /// Space taken by the panel's header and padding.
        public var chromeHeight: Double
        public var chromeWidth: Double
        /// The header row's own width; columns narrower than this waste space under it.
        public var headerWidth: Double
        public var maxWidth: Double
        public var maxHeight: Double

        public init(columnWidth: Double, columnSpacing: Double, rowHeight: Double, chromeHeight: Double,
                    chromeWidth: Double, headerWidth: Double, maxWidth: Double, maxHeight: Double) {
            self.columnWidth = columnWidth
            self.columnSpacing = columnSpacing
            self.rowHeight = rowHeight
            self.chromeHeight = chromeHeight
            self.chromeWidth = chromeWidth
            self.headerWidth = headerWidth
            self.maxWidth = maxWidth
            self.maxHeight = maxHeight
        }

        /// How much columns may widen to fill a header that's wider than them.
        public static let maxStretch = 1.45

        /// Column width for `n` columns: widened (up to `maxStretch`) to fill the header.
        public func columnWidth(for n: Int) -> Double {
            let n = Double(max(n, 1))
            let fill = (headerWidth - Double(n - 1) * columnSpacing) / n
            return min(max(columnWidth, fill), columnWidth * Self.maxStretch)
        }

        var maxColumns: Int {
            max(1, Int((maxWidth - chromeWidth + columnSpacing) / (columnWidth + columnSpacing)))
        }
    }

    /// Fewest rows a group piece may have; avoids a lone row stranded at the top or bottom of a column.
    public static let minChunk = 3
    /// Only groups at least this long are split across columns; shorter ones move whole, since
    /// a short group in two pieces reads worse than a slightly uneven column.
    public static let minSplitRows = 10

    /// Rows a group costs beyond its shortcuts: its title and the gap before the next group.
    /// Site groups also have a tinted card with padding.
    static func overhead(_ group: ShortcutGroup) -> Int {
        group.source == .site ? 3 : 2
    }

    public static func height(of column: [ShortcutGroup]) -> Int {
        column.reduce(0) { $0 + overhead($1) + $1.shortcuts.count }
    }

    /// How strongly empty space counts against a layout, relative to being the wrong shape.
    static let wasteWeight = 4.0

    /// Picks the column count that best balances two things: the panel's shape being close to
    /// `targetAspect` (width / height), and little empty space (ragged column ends, or a strip
    /// under a header that's wider than the columns). Layouts that don't fit `maxHeight` lose.
    public static func best(_ groups: [ShortcutGroup], metrics m: Metrics, targetAspect: Double) -> [[ShortcutGroup]] {
        guard !groups.isEmpty else { return [] }
        var best: (score: Double, columns: [[ShortcutGroup]])?
        var tallest: [[ShortcutGroup]] = []
        for n in 1...m.maxColumns {
            let columns = flow(groups, columns: n)
            tallest = columns
            let score = Self.score(columns, metrics: m, targetAspect: targetAspect)
            if score.fits, best == nil || score.value < best!.score { best = (score.value, columns) }
            if columns.count < n { break } // can't spread any further
        }
        return best?.columns ?? tallest
    }

    static func score(_ columns: [[ShortcutGroup]], metrics m: Metrics, targetAspect: Double) -> (value: Double, fits: Bool) {
        let heights = columns.map(height)
        let rows = Double(heights.max() ?? 0)
        let n = columns.count
        let colWidth = m.columnWidth(for: n)
        let contentWidth = Double(n) * colWidth + Double(n - 1) * m.columnSpacing
        let boxWidth = max(contentWidth, m.headerWidth)
        let width = boxWidth + m.chromeWidth
        let height = rows * m.rowHeight + m.chromeHeight
        // Share of the content area (below the header) that's blank.
        let used = Double(heights.reduce(0, +)) * m.rowHeight * colWidth
        let waste = rows > 0 ? 1 - used / (rows * m.rowHeight * boxWidth) : 0
        // Shape matters for big cheat sheets, which must fit the screen. A small panel (a few
        // page-specific groups) fits in any shape, so there filling it without gaps matters more.
        let screenShare = (width * height) / (m.maxWidth * m.maxHeight)
        let shapeWeight = min(1, 3 * screenShare)
        let value = shapeWeight * abs(log((width / height) / targetAspect)) + wasteWeight * waste
        return (value, height <= m.maxHeight && width <= m.maxWidth)
    }

    /// Flows groups into at most `n` columns of roughly equal height.
    public static func flow(_ groups: [ShortcutGroup], columns n: Int) -> [[ShortcutGroup]] {
        guard !groups.isEmpty else { return [] }
        let total = height(of: groups)
        var limit = max(minChunk, Int((Double(total) / Double(max(n, 1))).rounded(.up)))
        while true {
            let columns = fill(groups, limit: limit)
            if columns.count <= n { return columns }
            limit += 1
        }
    }

    /// Fills columns up to `limit` rows each, splitting groups where that keeps both pieces
    /// at least `minChunk` rows.
    static func fill(_ groups: [ShortcutGroup], limit: Int) -> [[ShortcutGroup]] {
        var columns: [[ShortcutGroup]] = [[]]
        var used = 0

        func newColumn() {
            columns.append([])
            used = 0
        }
        func place(_ group: ShortcutGroup, _ rows: ArraySlice<Shortcut>, part: Int) {
            var piece = group
            piece.shortcuts = Array(rows)
            piece.part = part
            columns[columns.count - 1].append(piece)
            used += overhead(group) + rows.count
        }

        for group in groups {
            var remaining = group.shortcuts[...]
            var part = 0
            if remaining.isEmpty { continue }
            let splittable = group.shortcuts.count >= minSplitRows
            while !remaining.isEmpty {
                let space = limit - used - overhead(group)
                let columnIsEmpty = columns[columns.count - 1].isEmpty
                if remaining.count <= space || (!splittable && columnIsEmpty) {
                    place(group, remaining, part: part)
                    remaining = []
                } else if splittable, space >= minChunk, min(space, remaining.count - minChunk) >= minChunk {
                    let take = min(space, remaining.count - minChunk)
                    place(group, remaining.prefix(take), part: part)
                    remaining = remaining.dropFirst(take)
                    part += 1
                    newColumn()
                } else if columnIsEmpty {
                    // Nothing splits nicely and the column is empty: take what fits (or the whole
                    // group if the rest would be too small) so we always make progress.
                    let fit = max(space, minChunk)
                    let take = remaining.count - fit < minChunk ? remaining.count : fit
                    place(group, remaining.prefix(take), part: part)
                    remaining = remaining.dropFirst(take)
                    part += 1
                    if !remaining.isEmpty { newColumn() }
                } else {
                    newColumn()
                }
            }
        }
        return columns.filter { !$0.isEmpty }
    }
}
