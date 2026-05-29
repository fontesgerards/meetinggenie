import SwiftUI
import NotchCore

/// Observable state bridge between the AppKit `PeekController` and the SwiftUI
/// `PeekView` hosted inside the panel (plan unit U8).
@available(macOS 13, *)
final class PeekModel: ObservableObject {
    @Published var title: String = ""
    @Published var points: [Point] = []
    @Published var quickAddVisible: Bool = false
    @Published var topInset: CGFloat = 0   // notch/menu-bar band height to clear
    @Published var notchWidth: CGFloat = 0 // physical notch width (0 = no notch)

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
    static let width: CGFloat = 360

    @ObservedObject var model: PeekModel
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    /// Menu-bar-safe T-shape when on a notch display (tab = notch width within
    /// the band, widening below it); plain concave-top rounded shape otherwise.
    private var peekClip: AnyShape {
        if model.topInset > 0, model.notchWidth > 1, model.notchWidth < Self.width {
            return AnyShape(NotchTShape(
                notchWidth: model.notchWidth,
                bandHeight: model.topInset,
                shoulderRadius: 12,
                bottomRadius: 20
            ))
        }
        return AnyShape(NotchShape(topCornerRadius: 11, bottomCornerRadius: 20))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))

                ForEach(Array(model.points.enumerated()), id: \.offset) { index, point in
                    Button {
                        model.onToggle(index)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: point.checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(point.checked ? Color.green : Color.white.opacity(0.5))
                            Text(point.text)
                                .strikethrough(point.checked, color: .white.opacity(0.4))
                                .foregroundStyle(point.checked ? Color.white.opacity(0.45) : Color.white)
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
                    .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer(minLength: 4)

            // Dedicated dismiss affordance, separate from the list body (R14).
            Button {
                model.onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Done — archive these points")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, model.topInset + 8) // clear the notch
        .frame(width: Self.width, alignment: .leading)
        .background(Color.black)
        .clipShape(peekClip)
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
