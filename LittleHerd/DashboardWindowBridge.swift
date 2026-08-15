import AppKit
import SwiftUI

enum DashboardWindowPresentation: Equatable {
    case splash
    case dashboard
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

        guard !reduceMotion else {
            window.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
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

        window.setFrame(
            NSRect(
                x: currentCenter.x - 150,
                y: currentCenter.y - 125,
                width: 300,
                height: 250
            ),
            display: true
        )

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.cornerRadius = 26
        contentView.layer?.masksToBounds = true
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

        window.setFrame(splashFrame, display: true)
        window.invalidateShadow()

        guard !reduceMotion else {
            window.setFrame(dashboardFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            window.animator().setFrame(dashboardFrame, display: true)
        }
    }
}
