import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageFilePickerButton: View {
    @Binding var image: NSImage?
    @Binding var url: URL?

    var title = "Choose image from disk"

    var body: some View {
        Button {
            pick()
        } label: {
            Label(title, systemImage: "folder")
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]

        if panel.runModal() == .OK, let pickedURL = panel.url {
            url = pickedURL
            image = NSImage(contentsOf: pickedURL)   // simple load; OK for images
        }
    }
}
