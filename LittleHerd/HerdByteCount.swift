import Foundation

/// How this app writes an amount of storage.
///
/// **No decimals below a terabyte.** `369 GB free` is the same fact as
/// `368.99 GB free` and two characters shorter, and the hundredths were never
/// once the thing anyone was reading — a disk that gains and loses a gigabyte
/// while you watch does not have a meaningful second decimal place. Terabytes
/// keep theirs, because `2 TB` and `2.43 TB` are half a disk apart.
///
/// Only storage. Memory keeps its decimals: a machine's RAM is a fixed number
/// that people know the shape of, and `23.31 GB of 24 GB` says something that
/// `23 GB of 24 GB` does not.
nonisolated enum HerdByteCount {
    private static let gigabyte: Int64 = 1_000_000_000
    private static let terabyte: Int64 = 1_000_000_000_000

    static func storage(_ bytes: Int64) -> String {
        rounded(bytes).formatted(.byteCount(style: .file))
    }

    /// The value the formatter is given, exposed so the rule can be tested
    /// without asserting on strings that change with the user's locale.
    ///
    /// Rounded rather than truncated: 368.99 GB is 369, not 368. And left
    /// alone below a gigabyte, where rounding to the nearest one turns half a
    /// gigabyte into "Zero kB" — which is what the first version of this did.
    static func rounded(_ bytes: Int64) -> Int64 {
        guard bytes >= gigabyte, bytes < terabyte else { return bytes }
        return Int64((Double(bytes) / Double(gigabyte)).rounded()) * gigabyte
    }
}
