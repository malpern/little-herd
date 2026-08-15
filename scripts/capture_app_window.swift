import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 4 else {
    fatalError("usage: capture_app_window.swift OWNER TITLE OUTPUT")
}

let owner = CommandLine.arguments[1]
let title = CommandLine.arguments[2]
let output = CommandLine.arguments[3]

let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

guard let window = windows.first(where: {
          ($0[kCGWindowOwnerName as String] as? String) == owner
              && ($0[kCGWindowName as String] as? String) == title
              && ($0[kCGWindowLayer as String] as? Int) == 0
      }),
      let windowNumber = window[kCGWindowNumber as String] as? Int
else {
    fputs("unable to find on-screen window for \(owner): \(title)\n", stderr)
    for window in windows where
        (window[kCGWindowOwnerName as String] as? String)?.localizedCaseInsensitiveContains(owner) == true
            || (window[kCGWindowName as String] as? String)?.localizedCaseInsensitiveContains(title) == true
    {
        let candidateOwner = window[kCGWindowOwnerName as String] as? String ?? "?"
        let candidateTitle = window[kCGWindowName as String] as? String ?? "?"
        let candidateLayer = window[kCGWindowLayer as String] as? Int ?? -1
        let candidateNumber = window[kCGWindowNumber as String] as? Int ?? -1
        let candidateBounds = window[kCGWindowBounds as String] ?? "?"
        fputs(
            "candidate owner=\(candidateOwner) title=\(candidateTitle) layer=\(candidateLayer) number=\(candidateNumber) bounds=\(candidateBounds)\n",
            stderr
        )
    }
    exit(1)
}

let capturedBounds = window[kCGWindowBounds as String] ?? "?"
fputs(
    "capturing owner=\(owner) title=\(title) number=\(windowNumber) bounds=\(capturedBounds)\n",
    stderr
)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
process.arguments = ["-x", "-o", "-l", String(windowNumber), output]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
