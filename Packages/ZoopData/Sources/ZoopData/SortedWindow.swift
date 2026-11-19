import Foundation

/// Binary bounds for sorted samples. Retains neighbouring points for line clipping.
public enum SortedWindow {
    public static func lowerBound<T>(_ values: [T], value: Double, key: (T) -> Double) -> Int {
        var low = 0, high = values.count
        while low < high {
            let middle = low + (high - low) / 2
            if key(values[middle]) < value { low = middle + 1 } else { high = middle }
        }
        return low
    }
    public static func range<T>(_ values: [T], from: Double, to: Double, padding: Int = 0, key: (T) -> Double) -> Range<Int> {
        let start = lowerBound(values, value: from, key: key)
        let end = lowerBound(values, value: to, key: key)
        return max(0, start - padding)..<min(values.count, end + padding)
    }
}
