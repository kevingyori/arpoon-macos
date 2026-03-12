import AppKit
import SwiftUI

@MainActor
final class SearchPaletteController {
    private let panel: NSPanel
    private let viewModel: SearchViewModel

    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.center()
        panel.contentViewController = NSHostingController(rootView: SearchPaletteView(viewModel: viewModel))
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        viewModel.refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func refresh() {
        viewModel.refresh()
    }
}
