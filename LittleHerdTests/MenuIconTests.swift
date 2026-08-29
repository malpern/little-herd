import AppKit
import Testing

@testable import LittleHerd

/// Whether the images a menu asks for exist at all.
///
/// The menu drew no icons and there are two explanations — the images do not
/// resolve, or the menu on screen is not the one being built. This separates
/// them without guessing.
@MainActor
@Suite("Menu icons resolve")
struct MenuIconTests {
    @Test
    func everyAnimalHasAnImage() {
        for avatar in HerdwareAvatar.allCases {
            #expect(
                NSImage(named: avatar.assetName) != nil,
                "no image for \(avatar.assetName)"
            )
        }
    }

    @Test
    func everySymbolTheMenusUseExists() {
        for name in [
            "sparkles", "apple.terminal", "display", "globe", "folder",
            "doc.on.doc", "arrow.clockwise", "number", "questionmark.circle",
        ] {
            #expect(
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                "no symbol named \(name)"
            )
        }
    }

    /// And that the built menu actually carries them.
    @Test
    func theBuiltMenuCarriesItsImages() {
        let machine = MachineConfiguration(
            id: MachineID("m"), name: "Mac mini", shortName: "Mini",
            hostname: "openclaw.local", hardwareSummary: "",
            platform: .macOS, connection: .ssh, avatar: .calfMini,
            identityFile: nil, sshUser: "malpern", serverNames: [],
            supportsGPU: false
        )
        let items = MachineMenuItems.items(
            for: machine,
            onOpenPage: {},
            onOpenAgents: {},
            open: { _ in }
        )
        let view = ContextMenuHostView()
        view.items = items
        let menu = view.menu(
            for: NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )!
        )
        let withImages = menu?.items.filter { $0.image != nil }.count ?? 0
        #expect(withImages > 0, "the menu was built without any images")
        #expect(menu?.items.first?.image != nil, "no animal on the first row")
    }
}
