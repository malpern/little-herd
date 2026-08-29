import AppKit
import SwiftUI

/// A right-click menu built in AppKit, so its items can carry images.
///
/// **SwiftUI's `.contextMenu` drops icons on macOS.** It accepts a `Label` with
/// an image, compiles, and then the system draws text only — which is why the
/// animal never appeared. `NSMenuItem` has an `image` property and the system
/// honours it; the limitation was the bridge, not the platform.
///
/// Everything a menu does for free is kept: keyboard navigation, Escape,
/// submenus, VoiceOver, and the system's own drawing.
struct AppKitContextMenu: NSViewRepresentable {
    let items: [AppKitMenuItem]

    func makeNSView(context: Context) -> ContextMenuHostView {
        let view = ContextMenuHostView()
        view.items = items
        return view
    }

    func updateNSView(_ view: ContextMenuHostView, context: Context) {
        view.items = items
    }
}

/// One row: a title, something to draw beside it, and what it does.
nonisolated struct AppKitMenuItem {
    enum Icon {
        case none
        case symbol(String)
        /// An asset, which is the point of the exercise — the machine's animal.
        case asset(String)
        case image(NSImage)
    }

    let title: String
    var icon: Icon = .none
    /// A separator, drawn instead of a row.
    var isSeparator = false
    /// **A row that cannot be chosen still says something.** A machine that
    /// will not take this work is listed and disabled, with the reason beside
    /// it — which is the thing a drag cannot do: it simply refuses, and
    /// silence is what had somebody asking whether transfers were on at all.
    var isEnabled = true
    var submenu: [AppKitMenuItem] = []
    var action: (() -> Void)?

    static var separator: AppKitMenuItem {
        AppKitMenuItem(title: "", isSeparator: true)
    }
}

/// The view that owns the menu.
///
/// **It claims right-clicks and nothing else.** An `NSView` laid over the herd
/// would otherwise take the mouse from the SwiftUI views underneath, and the
/// thing underneath here is the agent drag — which has already been broken once
/// by a layering change. `hitTest` looks at the event being dispatched and
/// returns nothing at all unless it is the one this view is for.
final class ContextMenuHostView: NSView {
    var items: [AppKitMenuItem] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return super.hitTest(point)
        case .leftMouseDown, .leftMouseUp
            where event.modifierFlags.contains(.control):
            return super.hitTest(point)
        default:
            return nil
        }
    }

    private static var submenuOwnerKey: UInt8 = 0

    override func menu(for event: NSEvent) -> NSMenu? { buildMenu() }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // Items are enabled by what they say, not by whether a responder
        // claims them: without this AppKit greys out every row whose target
        // it cannot validate.
        menu.autoenablesItems = false
        for item in items {
            guard !item.isSeparator else {
                menu.addItem(.separator())
                continue
            }
            let entry = NSMenuItem(
                title: item.title,
                action: item.action == nil ? nil : #selector(runMenuItem(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = item.action.map(ActionBox.init)
            entry.isEnabled = item.isEnabled
            if !item.submenu.isEmpty {
                let child = ContextMenuHostView()
                child.items = item.submenu
                entry.submenu = child.buildMenu()
                // The child view is retained by the menu it built, so the
                // submenu's actions outlive this call.
                objc_setAssociatedObject(
                    entry, &Self.submenuOwnerKey, child, .OBJC_ASSOCIATION_RETAIN
                )
            }
            if let icon = image(for: item.icon) {
                entry.image = icon
                // **And in the title as well.** Setting `image` alone drew
                // nothing here — the menu came up with no image column at all,
                // while a unit test confirmed the items were carrying their
                // images. Rather than keep guessing at why the image slot is
                // being ignored, the icon also goes into the title as a text
                // attachment, which is drawn as part of the string and so
                // cannot be dropped by whatever was dropping the other.
                entry.attributedTitle = title(item.title, with: icon)
            }
            menu.addItem(entry)
        }
        return menu
    }

    private func image(for icon: AppKitMenuItem.Icon) -> NSImage? {
        let found: NSImage? = switch icon {
        case .none: nil
        case .symbol(let name):
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .asset(let name): NSImage(named: name)
        case .image(let image): image
        }
        // Menu icons are drawn at about this size whatever they arrive as, and
        // an unresized 256-point avatar makes the row itself tall.
        found?.size = NSSize(width: 16, height: 16)
        return found
    }

    /// The icon and the title as one string.
    private func title(_ text: String, with icon: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = icon
        // Sat on the text baseline rather than above it, which is what an
        // attachment does by default and which makes every row taller.
        attachment.bounds = CGRect(x: 0, y: -3, width: 16, height: 16)

        let line = NSMutableAttributedString(attachment: attachment)
        line.append(NSAttributedString(string: "  " + text))
        return line
    }

    @objc private func runMenuItem(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.run()
    }

    private final class ActionBox {
        private let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
        func run() { body() }
    }
}
