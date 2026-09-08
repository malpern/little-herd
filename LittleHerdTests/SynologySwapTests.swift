import Foundation
import Testing

@testable import LittleHerd

/// Reading what the NAS has paged out.
@Suite("Synology swap")
struct SynologySwapTests {
    private func payload(total: Double?, available: Double?) -> DSMUtilizationPayload {
        let json: [String: Any] = [
            "memory": [
                "total_swap": total as Any,
                "avail_swap": available as Any,
            ].compactMapValues { $0 is NSNull ? nil : $0 }
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(DSMUtilizationPayload.self, from: data)
    }

    /// The figures the real NAS returned on 7 September, in DSM's kilobytes.
    @Test
    func itreadsTheRealNASFigures() throws {
        let swap = try #require(
            SynologyDSMParser.swapUsage(from: payload(total: 3_317_676, available: 2_997_184))
        )
        #expect(swap.totalBytes == 3_317_676 * 1024)
        #expect(swap.usedBytes == (3_317_676 - 2_997_184) * 1024)
        #expect(swap.isConfigured)
        // DSM's own swap_usage said 9%; ours should agree to the nearest point.
        #expect((swap.usedBytes / swap.totalBytes * 100).rounded() == 10)
    }

    /// **A total of nothing is "no swap", not "swap that is empty".** Nil rather than a
    /// zeroed reading, which is the distinction `isConfigured` exists to keep.
    @Test
    func noswapConfiguredReadsAsNothingAtAll() {
        #expect(SynologyDSMParser.swapUsage(from: payload(total: 0, available: 0)) == nil)
    }

    /// Half an answer is no answer: a NAS that reports available without a total has
    /// told us nothing we can size.
    @Test
    func amissingHalfIsNil() {
        #expect(SynologyDSMParser.swapUsage(from: payload(total: nil, available: 2_997_184)) == nil)
        #expect(SynologyDSMParser.swapUsage(from: payload(total: 3_317_676, available: nil)) == nil)
    }

    /// Available above total would make used negative, which is not a thing.
    @Test
    func usedNeverGoesBelowZero() throws {
        let swap = try #require(
            SynologyDSMParser.swapUsage(from: payload(total: 1000, available: 5000))
        )
        #expect(swap.usedBytes == 0)
    }
}

// No live harness here on purpose. Constructing a real `SynologyMetricsSampler`
// wants an endpoint, a pinned certificate, fallback names and a password provider,
// and the one thing a live test would prove — that the field is really called
// `total_swap` — was already established by asking DSM directly on 7 September:
// it answered 3,317,676, which is exactly what the NAS's own /proc/meminfo reports
// as SwapTotal. The figures above are that reading.
