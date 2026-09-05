import SwiftUI

extension EnvironmentValues {
    /// True while a view is being drawn into a still image rather than onto a
    /// screen — `PanelRenderHarness`, and nothing else.
    ///
    /// **`ImageRenderer` cannot flatten an `NSViewRepresentable`.** Where one
    /// appears it paints a yellow square with a red no-entry sign — the same
    /// placeholder a `.borderless` button and an indeterminate `ProgressView`
    /// already get — and logs `Unable to render flattened version of
    /// PlatformViewRepresentableAdaptor`. That is what had the overview
    /// fixtures coming out yellow with four prohibition signs across them, and
    /// it reads exactly like a missing asset catalog, which is where the first
    /// hour went: every avatar and colour in the herd resolves fine from the
    /// test host, and the placeholder is not about assets at all.
    ///
    /// Both of this app's representables draw nothing on screen. The
    /// right-click menu is there for the events; the window bridge is there
    /// for the window. Standing in for them with `Color.clear` under a render
    /// is therefore not a lie about the picture — it *is* the picture, and
    /// leaving them in hides the views they cover.
    ///
    /// Anything else conforming to `NSViewRepresentable` needs to read this
    /// too, or it will put a prohibition sign over whatever it is attached to.
    @Entry var isRenderingStillImage = false
}
