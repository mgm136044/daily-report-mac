import SwiftUI
import AppKit
import PDFKit

/// A standalone window that shows a report PDF and can save it. Follows the app's
/// onboarding-window pattern (a plain NSWindow hosting SwiftUI), since the app is a
/// menu-bar (.accessory) app with no document scene.
@MainActor
final class PDFViewerController {
    static let shared = PDFViewerController()
    private var window: NSWindow?

    func show(data: Data, suggestedName: String) {
        let view = PDFViewerView(data: data, suggestedName: suggestedName)
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
            window.title = suggestedName          // VF-1: keep the titlebar in sync when reusing the window
        } else {
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.setContentSize(NSSize(width: 720, height: 900))
            w.title = suggestedName
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)   // .accessory app must activate to show a window
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct PDFViewerView: View {
    let data: Data
    let suggestedName: String
    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(data: data)
            Divider()
            HStack {
                Spacer()
                Button("PDF로 저장") { save() }.keyboardShortcut("s")
            }
            .padding(8)
        }
    }
    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}

/// SwiftUI wrapper around PDFKit's PDFView.
private struct PDFKitView: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView(); v.autoScales = true; v.document = PDFDocument(data: data); return v
    }
    func updateNSView(_ v: PDFView, context: Context) { v.document = PDFDocument(data: data) }
}
