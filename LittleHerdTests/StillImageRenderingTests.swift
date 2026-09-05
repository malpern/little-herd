import AppKit
import SwiftUI
import Testing
@testable import LittleHerd

/// That the render harness draws no prohibition signs.
///
/// `ImageRenderer` cannot flatten an `NSViewRepresentable`: it paints a yellow
/// square with a red no-entry sign through it and carries on, so the render
/// succeeds, the suite is green, and the picture a human is meant to judge has
/// a placeholder where the interface was. The overview fixtures spent weeks
/// like that — four signs on a yellow ground, one per machine's right-click
/// menu — and the symptom reads so exactly like a missing asset catalog that
/// the catalog is where anyone looks first. It is not; every avatar and colour
/// resolves fine from the test host.
///
/// **The two colours are measured, not written down, and both are needed.**
/// They are system colours and a literal would drift the first time Apple
/// retunes them. More to the point the app draws that same yellow itself — a
/// thermometer in the warning band is exactly it — so looking for the yellow
/// alone fails on an honest render. What no honest render has is that red
/// ring lying on that yellow, which is the pair this looks for.
@MainActor
struct StillImageRenderingTests {
    /// How far from a red pixel the yellow may be. The ring is antialiased
    /// against its own ground, so the two pure colours never touch.
    private static let ringReach = 4

    @Test
    func theFlagSuppressesThePlaceholder() throws {
        let sign = try prohibitionSign()

        let unsuppressed = try bitmap(of: AppKitContextMenu(items: []))
        #expect(
            marks(of: sign, in: unsuppressed) > 0,
            "the instrument does not find the placeholder it just calibrated on"
        )

        let suppressed = try bitmap(
            of: AppKitContextMenu(items: [])
                .environment(\.isRenderingStillImage, true)
        )
        #expect(
            marks(of: sign, in: suppressed) == 0,
            "the still-image flag left a platform-view placeholder behind"
        )
    }

    /// The real fixture, through the harness's own funnel: the flag reaching
    /// the representable is worth nothing if the funnel stops setting it.
    @Test
    func theOverviewRendersNoPlaceholder() throws {
        let sign = try prohibitionSign()
        let url = try PanelRenderHarness().render(
            CPUOverviewView(machines: [herd()], metric: .cpu),
            size: CGSize(width: 324, height: 222),
            named: "placeholder-guard"
        )
        let image = try #require(NSImage(contentsOf: url))
        let tiff = try #require(image.tiffRepresentation)
        let rendered = try #require(NSBitmapImageRep(data: tiff))
        #expect(
            marks(of: sign, in: rendered) == 0,
            """
            the overview render has a platform-view placeholder in it — \
            something in it is an NSViewRepresentable that does not read \
            EnvironmentValues.isRenderingStillImage
            """
        )
    }

    // MARK: - The sign itself

    private struct ProhibitionSign {
        let ground: Pixel
        let ring: Pixel
    }

    /// The placeholder, drawn on purpose so its colours can be read off it.
    private func prohibitionSign() throws -> ProhibitionSign {
        let drawn = try bitmap(of: AppKitContextMenu(items: []))
        let counts = census(of: drawn)
        let ranked = counts.sorted { $0.value > $1.value }
        // The ground is most of the square and the ring is the next thing in
        // it. If a future SwiftUI learns to flatten a representable there is
        // no placeholder to calibrate against, and this test is measuring
        // nothing — which it should say, rather than pass.
        #expect(
            ranked.count >= 2,
            """
            no platform-view placeholder to calibrate against — \
            ImageRenderer may have learned to flatten representables
            """
        )
        let ground = try #require(ranked.first).key
        let ring = try #require(ranked.dropFirst().first).key
        return ProhibitionSign(ground: ground, ring: ring)
    }

    /// How many pixels of the ring are lying on the ground it comes with.
    private func marks(of sign: ProhibitionSign, in bitmap: NSBitmapImageRep) -> Int {
        var found = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let pixel = bitmap.colorAt(x: x, y: y),
                      Pixel(pixel) == sign.ring,
                      hasGround(sign.ground, near: (x, y), in: bitmap)
                else { continue }
                found += 1
            }
        }
        return found
    }

    private func hasGround(
        _ ground: Pixel,
        near point: (x: Int, y: Int),
        in bitmap: NSBitmapImageRep
    ) -> Bool {
        let reach = Self.ringReach
        for dy in -reach...reach {
            for dx in -reach...reach {
                let x = point.x + dx
                let y = point.y + dy
                guard x >= 0, y >= 0,
                      x < bitmap.pixelsWide, y < bitmap.pixelsHigh,
                      let pixel = bitmap.colorAt(x: x, y: y)
                else { continue }
                if Pixel(pixel) == ground { return true }
            }
        }
        return false
    }

    // MARK: - Reading pixels

    /// A colour quantised enough to be a key. `NSColor`'s own equality does
    /// not survive a round trip through a bitmap.
    private struct Pixel: Hashable {
        let red: Int
        let green: Int
        let blue: Int

        init(_ colour: NSColor) {
            let srgb = colour.usingColorSpace(.sRGB) ?? colour
            red = Int((srgb.redComponent * 255).rounded())
            green = Int((srgb.greenComponent * 255).rounded())
            blue = Int((srgb.blueComponent * 255).rounded())
        }
    }

    private func bitmap(of view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(
            content: view.frame(width: 60, height: 60)
        )
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    private func census(of bitmap: NSBitmapImageRep) -> [Pixel: Int] {
        var counts: [Pixel: Int] = [:]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let colour = bitmap.colorAt(x: x, y: y),
                      colour.alphaComponent > 0.99
                else { continue }
                counts[Pixel(colour), default: 0] += 1
            }
        }
        return counts
    }

    /// One machine running one agent: enough to mount the right-click menu and
    /// the deck, which are the representables the overview carries.
    private func herd() -> MachineMonitorModel {
        let model = MachineMonitorModel(
            configuration: MachineConfiguration(
                id: MachineID("air"),
                name: "Air",
                shortName: "Air",
                hostname: "air.local",
                hardwareSummary: "Air",
                platform: .macOS,
                connection: .ssh,
                avatar: .chickLaptop,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false
            )
        )
        model.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.cpu: MetricReading(value: 51)],
                agentSessions: [
                    AgentSession(
                        id: "a",
                        provider: .claude,
                        projectName: "little-herd",
                        state: .active,
                        updatedAt: .now,
                        progress: nil,
                        title: "Something",
                        activity: nil,
                        model: "claude-opus-5",
                        workingDirectory: "/Users/x/code/little-herd"
                    )
                ]
            )
        )
        return model
    }
}
