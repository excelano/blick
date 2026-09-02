// QuickLookPreview.swift
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Quick Look presentation for a downloaded email attachment. QL's own chrome
// carries Share (Save to Files, open in another app) and a Done button, so this
// one surface covers view, save, and open — no separate share sheet needed. The
// bytes are written to a temp file first, because Quick Look previews file URLs
// and decides how to render from the filename's extension.

import SwiftUI
import QuickLook

/// Writes attachment bytes to a temp file Quick Look can preview. Kept in a
/// single reused subdirectory that is cleared on each write, so at most one
/// attachment's bytes sit on disk at a time and nothing accumulates.
enum AttachmentPreviewFile {
    static func write(_ data: Data, filename: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentPreview", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(safeName(filename))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Keep the extension (Quick Look renders by it) but strip path separators
    /// and colons so a hostile or odd filename can't escape the temp directory.
    private static func safeName(_ filename: String?) -> String {
        guard let filename, !filename.isEmpty else { return "attachment" }
        return filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }
}

/// Wraps a written temp-file URL so it can drive a `.sheet(item:)`. A fresh `id`
/// per download means tapping a second attachment re-presents Quick Look even if
/// the URL path is the reused temp location.
struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presents a file URL with Quick Look. Present it from a `.sheet`. The
/// `QLPreviewController` is wrapped in a `UINavigationController` so its Share
/// (Save to Files, open in another app) action has a navigation bar to live in —
/// presented bare, Quick Look has nowhere to draw that button.
struct QuickLookPreview: UIViewControllerRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return UINavigationController(rootViewController: preview)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL
        init(fileURL: URL) { self.fileURL = fileURL }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}
