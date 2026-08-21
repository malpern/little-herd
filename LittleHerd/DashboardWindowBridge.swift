import AppKit
import SwiftUI

enum DashboardWindowPresentation: Equatable {
    case splash
    case dashboard
}

/// Keeping a computed window frame wholly on screen.
///
/// Every frame this bridge works out is derived from where the window already
/// is: the splash centres itself on the dashboard, the dashboard centres back
/// on the splash, and a resize grows from the top-left. None of that asks
/// whether the result is somewhere a person can see. A saved position near an
/// edge therefore grows off it, and the splash is the worst case because it is
/// the largest of the three — 450 points wide against a 300-point dashboard.
///
/// Measured on this Mac, whose saved dashboard frame sits 32 points below the
/// bottom of the screen: the splash centred on it started 45 points below the
/// bottom edge and launched with its lower band cut off.
///
/// Pure, and separated from AppKit, so the arithmetic can be tested without a
/// window or a screen.
nonisolated enum WindowPlacement {
    /// How far a rescued window is kept from the edge it was hanging over.
    ///
    /// A pure clamp moves the window the least distance that makes it visible,
    /// which lands it flush against the edge — technically on screen and
    /// still reading as though it had been cut off, which is how the first
    /// version of this was reported. Far enough to look deliberate, near
    /// enough that a window is not dragged into the middle of the display.
    static let edgeMargin: CGFloat = 16

    /// - Parameters:
    ///   - visible: the screen's `visibleFrame` — what is left after the menu
    ///     bar and the Dock, which is the area a window may occupy.
    ///   - margin: the gap to keep from every edge. Applied whether or not the
    ///     window was hanging over one: a window resting exactly on the edge
    ///     of the visible area reads as cut off just as a window over it does,
    ///     which is how the first version of this was reported — the right
    ///     edge was rescued and the splash then sat flush on the bottom.
    ///     Ignored on an axis where the window is too big for it, since a
    ///     margin that cannot be honoured must not push the window back off
    ///     the far side.
    static func onScreen(
        _ frame: NSRect,
        within visible: NSRect,
        margin: CGFloat = edgeMargin
    ) -> NSRect {
        let room = visible.insetBy(dx: margin, dy: margin)
        let horizontal = frame.width <= room.width ? room : visible
        let vertical = frame.height <= room.height ? room : visible

        var placed = frame

        // A window larger than the screen cannot be contained. Pin its
        // top-left: that is where a title and the first row of content are,
        // and losing the bottom of a too-tall window beats losing the top.
        placed.origin.x = frame.width >= horizontal.width
            ? horizontal.minX
            : min(
                max(frame.minX, horizontal.minX),
                horizontal.maxX - frame.width
            )
        placed.origin.y = frame.height >= vertical.height
            ? vertical.maxY - frame.height
            : min(
                max(frame.minY, vertical.minY),
                vertical.maxY - frame.height
            )

        return placed
    }

    /// The display a frame belongs to, for a frame that may be largely or
    /// entirely off any of them.
    ///
    /// `NSWindow.screen` is nil once a window is fully off-screen, which is
    /// exactly the case that needs rescuing, so it cannot be used here.
    @MainActor
    static func screen(for frame: NSRect) -> NSScreen? {
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        if let containing = NSScreen.screens.first(
            where: { $0.frame.contains(centre) }
        ) {
            return containing
        }
        // Otherwise the display it overlaps most, so a window hanging off the
        // edge of a second monitor is pulled back onto that monitor rather
        // than being teleported to the main one.
        let overlapping = NSScreen.screens.max { lhs, rhs in
            let left = lhs.frame.intersection(frame)
            let right = rhs.frame.intersection(frame)
            return left.width * left.height < right.width * right.height
        }
        return overlapping ?? NSScreen.main
    }
}

struct DashboardWindowBridge: NSViewRepresentable {
    let presentation: DashboardWindowPresentation
    let reduceMotion: Bool
    let dashboardContentSize: NSSize

    func makeNSView(context: Context) -> DashboardWindowObserverView {
        DashboardWindowObserverView(
            presentation: presentation,
            reduceMotion: reduceMotion,
            dashboardContentSize: dashboardContentSize
        )
    }

    func updateNSView(
        _ nsView: DashboardWindowObserverView,
        context: Context
    ) {
        nsView.update(
            presentation: presentation,
            reduceMotion: reduceMotion,
            dashboardContentSize: dashboardContentSize
        )
    }
}

@MainActor
final class DashboardWindowObserverView: NSView {
    private struct NativeChrome {
        let styleMask: NSWindow.StyleMask
        let titleVisibility: NSWindow.TitleVisibility
        let titlebarAppearsTransparent: Bool
        let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
        let isMovableByWindowBackground: Bool
        let isOpaque: Bool
        let backgroundColor: NSColor
        let toolbarWasVisible: Bool?
        let closeButtonWasHidden: Bool?
        let miniaturizeButtonWasHidden: Bool?
        let zoomButtonWasHidden: Bool?
    }

    private var presentation: DashboardWindowPresentation
    private var reduceMotion: Bool
    private var dashboardContentSize: NSSize
    private weak var observedWindow: NSWindow?
    private var nativeChrome: NativeChrome?
    private var appliedPresentation: DashboardWindowPresentation?

    init(
        presentation: DashboardWindowPresentation,
        reduceMotion: Bool,
        dashboardContentSize: NSSize
    ) {
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.dashboardContentSize = dashboardContentSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        if observedWindow !== window {
            observedWindow = window
            nativeChrome = NativeChrome(
                styleMask: window.styleMask,
                titleVisibility: window.titleVisibility,
                titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                titlebarSeparatorStyle: window.titlebarSeparatorStyle,
                isMovableByWindowBackground: window.isMovableByWindowBackground,
                isOpaque: window.isOpaque,
                backgroundColor: window.backgroundColor,
                toolbarWasVisible: window.toolbar?.isVisible,
                closeButtonWasHidden: window.standardWindowButton(
                    .closeButton
                )?.isHidden,
                miniaturizeButtonWasHidden: window.standardWindowButton(
                    .miniaturizeButton
                )?.isHidden,
                zoomButtonWasHidden: window.standardWindowButton(
                    .zoomButton
                )?.isHidden
            )
            appliedPresentation = nil

            // The frame macOS restores from the autosave is not guaranteed to
            // be wholly visible: AppKit's own constraint keeps a window's
            // title bar reachable and lets the rest hang off. This herd's
            // saved dashboard frame sits 32 points below the bottom of the
            // screen, which is how it was saved and how it comes back.
            window.setFrame(placed(window.frame), display: false)
        }

        applyPresentationIfNeeded()
    }

    func update(
        presentation: DashboardWindowPresentation,
        reduceMotion: Bool,
        dashboardContentSize: NSSize
    ) {
        let sizeChanged = self.dashboardContentSize != dashboardContentSize
        self.presentation = presentation
        self.reduceMotion = reduceMotion
        self.dashboardContentSize = dashboardContentSize
        applyPresentationIfNeeded()

        // Moving between the overview and a machine changes the content size
        // without changing the presentation, so nothing above resizes the
        // window and the content gets clipped instead. Drive the frame here.
        if sizeChanged, presentation == .dashboard {
            resizeToDashboardContent()
        }
    }

    private func resizeToDashboardContent() {
        guard let window = observedWindow ?? self.window else { return }

        // The window draws under its titlebar (fullSizeContentView), so the
        // content size IS the frame size. Converting through
        // frameRect(forContentRect:) adds a titlebar that is already included
        // and leaves the content a few points short — enough to clip the
        // machine names off the bottom of the overview.
        let target = NSRect(origin: .zero, size: dashboardContentSize)
        guard abs(target.width - window.frame.width) > 0.5
            || abs(target.height - window.frame.height) > 0.5
        else {
            return
        }

        // Grow from the top-left so the titlebar stays put rather than the
        // window appearing to jump.
        let frame = NSRect(
            x: window.frame.origin.x,
            y: window.frame.maxY - target.height,
            width: target.width,
            height: target.height
        )

        // Growing from the top-left pushes the bottom edge down, so a window
        // already sitting low ends up partly under the Dock or off the screen.
        let placedFrame = placed(frame)
        guard !reduceMotion else {
            window.setFrame(placedFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(placedFrame, display: true)
        }
    }

    private func applyPresentationIfNeeded() {
        guard let window = observedWindow ?? self.window,
              let nativeChrome,
              appliedPresentation != presentation
        else {
            return
        }

        switch presentation {
        case .splash:
            applySplashChrome(to: window)

        case .dashboard:
            restoreNativeChrome(nativeChrome, to: window)
        }

        appliedPresentation = presentation
    }

    private func applySplashChrome(to window: NSWindow) {
        let currentCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)

        window.styleMask = window.styleMask.union(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar?.isVisible = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        let splashContentRect = NSRect(
            origin: .zero,
            size: LittleHerdSplashMetrics.contentSize
        )
        var splashFrame = window.frameRect(forContentRect: splashContentRect)
        splashFrame.origin = NSPoint(
            x: currentCenter.x - splashFrame.width / 2,
            y: currentCenter.y - splashFrame.height / 2
        )
        window.setFrame(placed(splashFrame), display: true)

        // And again once the window has settled. SwiftUI sizes the window from
        // its content under `.windowResizability(.contentSize)`, and that
        // happens after this runs: it keeps the top-left and grows downward,
        // which put the splash back flush on the bottom edge every time no
        // matter what was set here. Measured — the frame set above was correct
        // and the frame on screen was not.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            let settled = self.placed(window.frame)
            guard settled != window.frame else { return }
            window.setFrame(settled, display: true)
        }

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.cornerRadius = LittleHerdSplashMetrics.cornerRadius
        contentView.layer?.masksToBounds = true
        // Without this the layer keeps an opaque backing, and the mask's
        // antialiased edge blends the artwork against it — a pale halo tracing
        // every corner. The splash view clips itself to the same radius, so
        // this mask is now a second line of defence rather than the only one.
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        window.invalidateShadow()
    }

    private func restoreNativeChrome(
        _ nativeChrome: NativeChrome,
        to window: NSWindow
    ) {
        let splashFrame = window.frame

        window.styleMask = nativeChrome.styleMask
        window.titleVisibility = nativeChrome.titleVisibility
        window.titlebarAppearsTransparent = nativeChrome.titlebarAppearsTransparent
        window.titlebarSeparatorStyle = nativeChrome.titlebarSeparatorStyle
        window.toolbar?.isVisible = nativeChrome.toolbarWasVisible ?? true
        window.standardWindowButton(.closeButton)?.isHidden =
            nativeChrome.closeButtonWasHidden ?? false
        window.standardWindowButton(.miniaturizeButton)?.isHidden =
            nativeChrome.miniaturizeButtonWasHidden ?? false
        window.standardWindowButton(.zoomButton)?.isHidden =
            nativeChrome.zoomButtonWasHidden ?? false
        window.isMovableByWindowBackground = nativeChrome.isMovableByWindowBackground
        window.isOpaque = nativeChrome.isOpaque
        window.backgroundColor = nativeChrome.backgroundColor

        if let contentView = window.contentView {
            contentView.layer?.cornerRadius = 0
            contentView.layer?.masksToBounds = false
        }

        let dashboardContentRect = NSRect(
            origin: .zero,
            size: dashboardContentSize
        )
        var dashboardFrame = window.frameRect(forContentRect: dashboardContentRect)
        dashboardFrame.origin = NSPoint(
            x: splashFrame.midX - dashboardFrame.width / 2,
            y: splashFrame.midY - dashboardFrame.height / 2
        )

        window.setFrame(placed(splashFrame), display: true)
        window.invalidateShadow()

        let target = placed(dashboardFrame)
        guard !reduceMotion else {
            window.setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            window.animator().setFrame(target, display: true)
        }
    }

    /// The same frame, moved the least distance needed to be wholly visible.
    private func placed(_ frame: NSRect) -> NSRect {
        guard let visible = WindowPlacement.screen(for: frame)?.visibleFrame
        else {
            return frame
        }
        return WindowPlacement.onScreen(frame, within: visible)
    }
}
