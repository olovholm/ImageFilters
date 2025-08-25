
import SwiftUI

struct ContentView: View {
    @State private var image: NSImage?
    @State private var url: URL?

    @StateObject private var vm = FiltersViewModel()

    var body: some View {
        HStack(spacing: 24) {
            VStack(spacing: 12) {
                ImageFilePickerButton(image: $image, url: $url, title: "Choose image")
                Group {
                    if let img = vm.outputImage ?? image {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 360, height: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 8)
                    } else {
                        ContentUnavailableView("No image", systemImage: "photo")
                            .frame(width: 360, height: 360)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Filters").font(.headline)
                List {
                    ForEach($vm.filters) { $filter in
                        Toggle(isOn: $filter.enabled) {
                            Text(filter.name.replacingOccurrences(of: "fx_", with: ""))
                                .font(.body.monospaced())
                        }
                        .toggleStyle(.switch)
                    }
                }
                .frame(width: 260, height: 360)

                HStack {
                    Button("Apply") {
                        guard let img = image else { return }
                        vm.applySelected(to: img)
                    }
                    .keyboardShortcut(.return)

                    Button("Reset") {
                        vm.outputImage = nil
                        for i in vm.filters.indices { vm.filters[i].enabled = false }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}
