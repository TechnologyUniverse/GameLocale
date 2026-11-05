import AppKit

@MainActor
enum FolderSheet {
    static func present(_ panel: NSOpenPanel,
                        completion: @escaping @MainActor (NSApplication.ModalResponse) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            Task { @MainActor in completion(response) }
        }
        // Attach to a real application window, never to an auxiliary glass window.
        let parent = NSApp.keyWindow.flatMap { $0.canBecomeKey && !$0.isSheet ? $0 : nil }
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeKey && !$0.isSheet }
        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
