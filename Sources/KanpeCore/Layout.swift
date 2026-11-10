import Foundation

public enum ColumnLayout {
    /// Splits groups into at most `maxColumns` columns, in reading order, so that
    /// columns have roughly equal height. A group's height is its row count plus a header.
    public static func columns<T>(_ groups: [T], rows: (T) -> Int, maxColumns: Int, targetRowsPerColumn: Int) -> [[T]] {
        guard !groups.isEmpty else { return [] }
        let heights = groups.map { rows($0) + 2 }
        let total = heights.reduce(0, +)
        let wanted = Int((Double(total) / Double(max(targetRowsPerColumn, 1))).rounded(.up))
        let count = min(max(1, wanted), max(1, maxColumns), groups.count)
        let perColumn = Double(total) / Double(count)

        var result: [[T]] = [[]]
        var current = 0
        for (group, height) in zip(groups, heights) {
            // Start a new column when this group would push us past the even share,
            // unless the column is empty or we are already on the last column.
            if !result[result.count - 1].isEmpty,
               result.count < count,
               Double(current) + Double(height) / 2 > perColumn {
                result.append([])
                current = 0
            }
            result[result.count - 1].append(group)
            current += height
        }
        return result
    }
}
