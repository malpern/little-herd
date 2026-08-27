import Foundation
import Testing
@testable import LittleHerd

/// How storage is written.
struct HerdByteCountTests {
    /// The hundredths go, and the number is right rather than merely shorter.
    @Test
    func gigabytesLoseTheirDecimalsAndRoundRatherThanTruncate() {
        #expect(HerdByteCount.rounded(368_990_000_000) == 369_000_000_000)
        #expect(HerdByteCount.rounded(930_910_000_000) == 931_000_000_000)
        #expect(HerdByteCount.rounded(103_320_000_000) == 103_000_000_000)
    }

    /// A terabyte's decimals are half a disk apart and stay.
    @Test
    func terabytesKeepTheirDecimals() {
        #expect(HerdByteCount.rounded(2_430_000_000_000) == 2_430_000_000_000)
    }

    /// **Below a gigabyte, rounding to the nearest one is destruction.** The
    /// first attempt turned 512 MB into "Zero kB", which is not a smaller
    /// number but a different fact.
    @Test
    func anythingUnderAGigabyteIsLeftAlone() {
        #expect(HerdByteCount.rounded(512_000_000) == 512_000_000)
        #expect(HerdByteCount.rounded(0) == 0)
        #expect(HerdByteCount.rounded(1) == 1)
    }

    /// The boundaries themselves, so the two guards cannot drift apart.
    @Test
    func theBoundariesBelongToTheRuleTheyStart() {
        #expect(HerdByteCount.rounded(1_000_000_000) == 1_000_000_000)
        #expect(HerdByteCount.rounded(999_999_999) == 999_999_999)
        #expect(HerdByteCount.rounded(1_000_000_000_000) == 1_000_000_000_000)
    }

    /// And the rendered string, once, so a refactor cannot quietly reintroduce
    /// a decimal point.
    @Test
    func theWrittenFormHasNoDecimalPointBelowATerabyte() {
        #expect(!HerdByteCount.storage(368_990_000_000).contains("."))
        #expect(HerdByteCount.storage(2_430_000_000_000).contains("."))
    }
}
