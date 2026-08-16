import Foundation

/// One recorded point: the average of everything sampled inside a bucket.
nonisolated struct HistorySample: Codable, Equatable, Sendable {
    /// Start of the bucket this point covers.
    let timestamp: Date
    let value: Double
}

/// What a series has done over a window.
nonisolated struct HistoryTrend: Equatable, Sendable {
    let first: HistorySample
    let last: HistorySample
    let sampleCount: Int

    var change: Double { last.value - first.value }
    var duration: TimeInterval {
        last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// Whether the window is long enough for the change to mean anything. Two
    /// points a minute apart is not a trend, however different they are.
    var isMeaningful: Bool {
        sampleCount >= 3 && duration >= 30 * 60
    }
}

/// Names a thing worth remembering over time.
///
/// A string rather than `MetricKind` because the most valuable series is not a
/// metric at all: the uncorrectable-sector count of one drive, which is the
/// number that says whether a failing disk is failing faster.
nonisolated enum HistorySeries: Equatable, Hashable, Sendable {
    case metric(MetricKind)
    case driveSectors(driveID: String)
    case volumeUsedPercent(volumeID: String)

    var storageKey: String {
        switch self {
        case .metric(let kind): "metric:\(kind.rawValue)"
        case .driveSectors(let id): "drive-sectors:\(id)"
        case .volumeUsedPercent(let id): "volume-used:\(id)"
        }
    }
}

/// Remembers what the herd has been doing, so the interface can say whether
/// something is getting worse rather than only what it is right now.
///
/// Samples arrive every ten seconds, which is far more than is worth keeping for
/// a month. They are averaged into fixed buckets on the way in, so a month of
/// history is a few thousand points per series rather than a quarter of a
/// million, and the file stays small enough to rewrite whole.
actor MetricHistoryStore {
    /// Five minutes: fine enough to see a disk fill over an afternoon, coarse
    /// enough that a month fits comfortably in memory.
    static let bucketDuration: TimeInterval = 5 * 60
    static let defaultRetention: TimeInterval = 30 * 24 * 60 * 60

    private struct SeriesKey: Hashable, Codable {
        let machine: String
        let series: String
    }

    private struct Bucket {
        let start: Date
        var total: Double
        var count: Int

        var average: Double { count > 0 ? total / Double(count) : 0 }
    }

    private let fileURL: URL?
    private let retention: TimeInterval
    private var samples: [SeriesKey: [HistorySample]] = [:]
    /// The bucket currently being filled, kept apart so a partial average is
    /// never mistaken for a finished point.
    private var openBuckets: [SeriesKey: Bucket] = [:]
    private var isDirty = false

    init(fileURL: URL?, retention: TimeInterval = MetricHistoryStore.defaultRetention) {
        self.fileURL = fileURL
        self.retention = retention
        // Loaded here rather than in a task: the first read must not race the
        // first write, or a launch could persist an empty history over a real
        // one.
        samples = Self.loadSamples(from: fileURL, retention: retention)
    }

    /// The store used by the app, under Application Support.
    static func makeDefault() -> MetricHistoryStore {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("LittleHerd", isDirectory: true)

        if let directory {
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return MetricHistoryStore(
            fileURL: directory?.appendingPathComponent("history.json")
        )
    }

    // MARK: - Recording

    func record(
        machine: MachineID,
        series: HistorySeries,
        value: Double,
        at timestamp: Date = .now
    ) {
        let key = SeriesKey(
            machine: machine.rawValue,
            series: series.storageKey
        )
        let bucketStart = Self.bucketStart(for: timestamp)

        if var open = openBuckets[key] {
            if open.start == bucketStart {
                open.total += value
                open.count += 1
                openBuckets[key] = open
                return
            }
            // A new bucket began: the finished one becomes a point.
            append(
                HistorySample(timestamp: open.start, value: open.average),
                for: key,
                asOf: timestamp
            )
        }

        openBuckets[key] = Bucket(start: bucketStart, total: value, count: 1)
    }

    /// `asOf` is the time the newest reading arrived, not the time of the
    /// bucket being filed. Pruning against the bucket would measure retention
    /// from the wrong end and keep points well past their window.
    private func append(
        _ sample: HistorySample,
        for key: SeriesKey,
        asOf now: Date
    ) {
        var series = samples[key] ?? []
        series.append(sample)

        let oldest = now.addingTimeInterval(-retention)
        series.removeAll { $0.timestamp < oldest }

        samples[key] = series
        isDirty = true
    }

    // MARK: - Reading

    /// Finished points, plus the bucket in progress, so the most recent reading
    /// is never missing from a chart just because its bucket has not closed.
    func samples(
        machine: MachineID,
        series: HistorySeries,
        since: Date? = nil
    ) -> [HistorySample] {
        let key = SeriesKey(
            machine: machine.rawValue,
            series: series.storageKey
        )
        var points = samples[key] ?? []
        if let open = openBuckets[key] {
            points.append(
                HistorySample(timestamp: open.start, value: open.average)
            )
        }
        guard let since else { return points }
        return points.filter { $0.timestamp >= since }
    }

    func trend(
        machine: MachineID,
        series: HistorySeries,
        over window: TimeInterval,
        now: Date = .now
    ) -> HistoryTrend? {
        let points = samples(
            machine: machine,
            series: series,
            since: now.addingTimeInterval(-window)
        )
        guard let first = points.first, let last = points.last,
              first.timestamp < last.timestamp
        else {
            return nil
        }
        return HistoryTrend(
            first: first,
            last: last,
            sampleCount: points.count
        )
    }

    // MARK: - Persistence

    /// Rewrites the whole file. It is small by construction, and a partial
    /// history is worth less than the simplicity of not maintaining an index.
    func flush() {
        guard let fileURL, isDirty || !openBuckets.isEmpty else { return }

        // Buckets in progress are written too. They are five minutes wide, so
        // without this a session shorter than that would persist nothing at
        // all, and quitting would always discard the most recent readings —
        // which are the ones a trend needs most.
        var merged = samples
        for (key, open) in openBuckets {
            var series = merged[key] ?? []
            series.removeAll { $0.timestamp == open.start }
            series.append(
                HistorySample(timestamp: open.start, value: open.average)
            )
            merged[key] = series
        }

        let encodable = merged.reduce(into: [String: [HistorySample]]()) {
            result, entry in
            result["\(entry.key.machine)|\(entry.key.series)"] = entry.value
        }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        try? data.write(to: fileURL, options: .atomic)
        isDirty = false
    }

    private static func loadSamples(
        from fileURL: URL?,
        retention: TimeInterval
    ) -> [SeriesKey: [HistorySample]] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                  [String: [HistorySample]].self,
                  from: data
              )
        else {
            return [:]
        }

        var loaded: [SeriesKey: [HistorySample]] = [:]
        let oldest = Date.now.addingTimeInterval(-retention)
        for (composite, points) in decoded {
            let parts = composite.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let kept = points.filter { $0.timestamp >= oldest }
            guard !kept.isEmpty else { continue }
            loaded[
                SeriesKey(machine: String(parts[0]), series: String(parts[1]))
            ] = kept
        }
        return loaded
    }

    static func bucketStart(for timestamp: Date) -> Date {
        let interval = timestamp.timeIntervalSince1970
        return Date(
            timeIntervalSince1970: (interval / bucketDuration).rounded(.down)
                * bucketDuration
        )
    }
}
