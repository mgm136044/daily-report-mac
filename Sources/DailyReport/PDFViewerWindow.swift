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
    private var hosting: NSHostingController<PDFViewerView>?

    func show(data: Data, suggestedName: String) {
        let view = PDFViewerView(data: data, suggestedName: suggestedName)
        if let window, let hosting {
            // Reuse (VF-1): update the SwiftUI content IN PLACE. Reassigning contentViewController
            // makes AppKit resize the window to the fitting size once — collapsing it to ~1×0 (VF-2),
            // which `sizingOptions = []` does NOT prevent. Setting rootView leaves the frame alone.
            hosting.rootView = view
            window.title = suggestedName
        } else {
            let hc = makeHosting(view)
            let w = NSWindow(contentViewController: hc)
            // styleMask first, THEN sizes: setting styleMask afterwards can reset the window's
            // content-size floor (contentMinSize was observed cleared to 0×0 when set before it).
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.setContentSize(NSSize(width: 720, height: 900))
            w.contentMinSize = NSSize(width: 560, height: 680)
            w.title = suggestedName
            w.center()
            window = w
            hosting = hc
        }
        NSApp.activate(ignoringOtherApps: true)   // .accessory app must activate to show a window
        window?.makeKeyAndOrderFront(nil)
    }

    /// Host `view` without letting NSHostingController shrink the window to the SwiftUI fitting
    /// size. By default the controller collapses the window to the content's intrinsic size — and
    /// `PDFKitView` (a scroll view) has none — which silently overrode `setContentSize(720×900)`
    /// and made the window open tiny. `sizingOptions = []` disables that auto-fit. Both the
    /// first-create and the reuse (VF-1) paths route through here so neither re-collapses.
    private func makeHosting(_ view: PDFViewerView) -> NSHostingController<PDFViewerView> {
        let hc = NSHostingController(rootView: view)
        hc.sizingOptions = []
        return hc
    }
}

private struct PDFViewerView: View {
    let data: Data
    let suggestedName: String
    var body: some View {
        VStack(spacing: 0) {
            PDFKitView(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // fill the window; PDFView has no intrinsic size
            Divider()
            HStack {
                Spacer()
                Button("PDF로 저장") { save() }.keyboardShortcut("s")
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
