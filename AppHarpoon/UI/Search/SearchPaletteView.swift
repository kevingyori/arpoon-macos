import SwiftUI

struct SearchPaletteView: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            searchField
            results
            actions
        }
        .padding(18)
        .frame(minWidth: 680, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search Targets")
                .font(.system(size: 19, weight: .semibold))

            Text("Search running apps, live windows, and saved slots.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        TextField("Search apps, windows, or slots", text: $viewModel.query)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 14))
            .onSubmit {
                viewModel.jumpSelection()
            }
    }

    private var results: some View {
        List(selection: $viewModel.selectedID) {
            ForEach(viewModel.filteredItems, id: \.id) { item in
                SearchResultRow(item: item)
                    .tag(item.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Jump") {
                viewModel.jumpSelection()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedItem == nil)

            Picker("Bind to slot", selection: $viewModel.bindSlot) {
                ForEach(1 ... 9, id: \.self) { slot in
                    Text("\(slot)").tag(slot)
                }
            }
            .pickerStyle(.segmented)

            Button("Bind") {
                viewModel.bindSelection()
            }
            .disabled(viewModel.selectedItem == nil)

            Button("Clear Slot") {
                viewModel.clearSelectionIfNeeded()
            }
            .disabled(!viewModel.canClearSelectedSlot)

            Spacer()

            Button("Close") {
                viewModel.dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

private struct SearchResultRow: View {
    let item: SearchItem

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleId: item.bundleId)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(item.kindLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 999).fill(Color.secondary.opacity(0.12)))
        }
        .padding(.vertical, 2)
    }
}

private extension SearchItem {
    var kindLabel: String {
        switch self {
        case .slot:
            return "Slot"
        case .app:
            return "App"
        case .window:
            return "Window"
        }
    }
}
