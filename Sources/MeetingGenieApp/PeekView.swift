import SwiftUI
import NotchCore

/// Observable state bridge between the AppKit `PeekController` and the SwiftUI
/// `PeekView` hosted inside the panel (plan unit U8).
@available(macOS 13, *)
final class PeekModel: ObservableObject {
    @Published var title: String = ""
    @Published var points: [Point] = []
    @Published var quickAddVisible: Bool = false

    var onToggle: (Int) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onQuickAddBegin: () -> Void = {}
    var onQuickAddSubmit: (String) -> Void = { _ in }
}

/// The peek's contents: the points list with check-off, a quick-add field, and
/// a dismiss control that is deliberately separate from the list body so a
/// stray tap can't archive the list (origin R12, R13, R14, R25; AE4).
@available(macOS 13, *)
struct PeekView: View {
    @ObservedObject var model: PeekModel
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                ForEach(Array(model.points.enumerated()), id: \.offset) { index, point in
                    Button {
                        model.onToggle(index)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: point.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(point.checked ? .green : .secondary)
                            Text(point.text)
                                .strikethrough(point.checked, color: .secondary)
                                .foregroundStyle(point.checked ? .secondary : .primary)
                                .lineLimit(2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if model.quickAddVisible {
                    TextField("Add a point…", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .font(.caption)
                        .onSubmit(submit)
                } else {
                    Button {
                        model.quickAddVisible = true
                        model.onQuickAddBegin() // deliberate focus handoff (R25)
                    } label: {
                        Label("Add point", systemImage: "plus.circle")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            // Dedicated dismiss affordance, separate from the list body (R14).
            Button {
                model.onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Done — archive these points")
        }
        .padding(10)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: model.quickAddVisible) { visible in
            if visible { fieldFocused = true }
        }
    }

    private func submit() {
        let text = draft
        draft = ""
        model.quickAddVisible = false
        model.onQuickAddSubmit(text)
    }
}
