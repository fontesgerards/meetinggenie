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

/// Design tokens lifted from the MeetingGenie design system
/// (`colors_and_type.css`). Monochrome-plus-one: white at a graded opacity
/// ladder over true black, with one green for the checked state.
@available(macOS 13, *)
enum MGTheme {
    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255) // systemGreen dark #30D158

    // Opacity ladder (the entire neutral system).
    static let secondary = Color.white.opacity(0.55) // time label, "Add point"
    static let iconIdle = Color.white.opacity(0.50)  // hollow circle, ×
    static let iconHover = Color.white.opacity(0.80) // hover bumps one rung
    static let dismissHover = Color.white.opacity(0.85)
    static let doneText = Color.white.opacity(0.45)
    static let strike = Color.white.opacity(0.40)
    static let fieldFill = Color.white.opacity(0.08)
    static let fieldBorder = Color.white.opacity(0.10)
    static let fieldBorderFocus = Color.white.opacity(0.25)
    static let placeholder = Color.white.opacity(0.35)

    // Type scale (px → SF Pro system sizes).
    static let sizeCaption: CGFloat = 12  // point rows, field
    static let sizeCaption2: CGFloat = 11 // time, "Add point"

    // Motion.
    static let easeOut = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
    static let tickDuration: Double = 0.14
}

/// Quiet, tactile press feedback: a slight shrink on press, calm ease-out.
@available(macOS 13, *)
struct PeekButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// One talking-point row (origin R12). Unchecked: hollow circle + white text;
/// checked: green checkmark (with a one-permissible-flourish scale punch) +
/// dimmed, struck-through text. Hover raises the idle icon one opacity rung.
@available(macOS 13, *)
private struct PointRowView: View {
    let point: Point
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: point.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(point.checked ? MGTheme.green : (hovering ? MGTheme.iconHover : MGTheme.iconIdle))
                    .scaleEffect(point.checked ? 1.06 : 1.0)
                    .animation(.easeOut(duration: MGTheme.tickDuration), value: point.checked)
                Text(point.text)
                    .font(.system(size: MGTheme.sizeCaption, weight: .medium))
                    .foregroundStyle(point.checked ? MGTheme.doneText : Color.white)
                    .strikethrough(point.checked, color: MGTheme.strike)
                    .lineLimit(2)
                    .animation(.easeOut(duration: MGTheme.tickDuration), value: point.checked)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(PeekButtonStyle())
        .onHover { hovering = $0 }
    }
}

/// The peek's contents: the points list with check-off, a quick-add field, and
/// a dismiss control deliberately separate from the list body (origin R12–R14,
/// R25; AE4).
@available(macOS 13, *)
struct PeekView: View {
    static let width: CGFloat = 360

    @ObservedObject var model: PeekModel
    @State private var draft: String = ""
    @State private var dismissHovering = false
    @State private var addHovering = false
    @FocusState private var fieldFocused: Bool

    /// Menu-bar-safe T-shape on a notch display; plain concave-top rounded shape otherwise.
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
                    .font(.system(size: MGTheme.sizeCaption2))
                    .tracking(0.1)
                    .foregroundStyle(MGTheme.secondary)

                ForEach(Array(model.points.enumerated()), id: \.offset) { index, point in
                    PointRowView(point: point) { model.onToggle(index) }
                }

                quickAdd
            }

            Spacer(minLength: 4)

            // Dedicated dismiss affordance, separate from the list body (R14).
            Button {
                model.onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(dismissHovering ? MGTheme.dismissHover : MGTheme.iconIdle)
            }
            .buttonStyle(PeekButtonStyle())
            .onHover { dismissHovering = $0 }
            .help("Done — archive these points")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, model.topInset + 8) // clear the notch
        .frame(width: Self.width, alignment: .leading)
        .background(Color.black)
        .clipShape(peekClip)
        .animation(MGTheme.easeOut, value: model.quickAddVisible)
        .onChange(of: model.quickAddVisible) { visible in
            if visible { fieldFocused = true } else { draft = "" }
        }
    }

    @ViewBuilder
    private var quickAdd: some View {
        if model.quickAddVisible {
            ZStack(alignment: .leading) {
                if draft.isEmpty {
                    Text("Add a point…")
                        .font(.system(size: MGTheme.sizeCaption))
                        .foregroundStyle(MGTheme.placeholder)
                        .padding(.horizontal, 8)
                }
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: MGTheme.sizeCaption))
                    .foregroundStyle(Color.white)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Add a point…") // empty title needs an explicit label for VoiceOver
            }
            .background(MGTheme.fieldFill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(fieldFocused ? MGTheme.fieldBorderFocus : MGTheme.fieldBorder, lineWidth: 1)
            )
            .padding(.top, 4)
            .transition(.opacity)
        } else {
            Button {
                model.quickAddVisible = true
                model.onQuickAddBegin() // deliberate focus handoff (R25)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle").font(.system(size: 14))
                    Text("Add point").font(.system(size: MGTheme.sizeCaption2))
                }
                .foregroundStyle(addHovering ? MGTheme.iconHover : MGTheme.secondary)
            }
            .buttonStyle(PeekButtonStyle())
            .onHover { addHovering = $0 }
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func submit() {
        let text = draft
        draft = ""
        model.quickAddVisible = false
        model.onQuickAddSubmit(text)
    }
}
