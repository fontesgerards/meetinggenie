import SwiftUI
import NotchCore

/// Observable state bridge between the AppKit `PeekController` and the SwiftUI
/// `PeekView` hosted inside the panel (plan units U7, U8, and review-navigation U2/U3/U5).
@available(macOS 13, *)
final class PeekModel: ObservableObject {
    @Published var title: String = ""
    @Published var points: [Point] = []
    @Published var quickAddVisible: Bool = false
    @Published var topInset: CGFloat = 0   // notch/menu-bar band height to clear
    @Published var notchWidth: CGFloat = 0 // physical notch width (0 = no notch)

    // Browse navigation (review-navigation feature).
    @Published var kind: ReviewKind = .active   // recency of the shown entry
    @Published var isBrowsing: Bool = false
    @Published var canPrev: Bool = false
    @Published var canNext: Bool = false
    @Published var nowBadge: Bool = false       // a meeting went live during browse
    @Published var emptyMessage: String? = nil  // shown when there's nothing to browse

    var onToggle: (Int) -> Void = { _ in }
    var onRemove: (Int) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onQuickAddBegin: () -> Void = {}
    var onQuickAddSubmit: (String) -> Void = { _ in }
    var onPrev: () -> Void = {}
    var onNext: () -> Void = {}
}

/// Design tokens lifted from the MeetingGenie design system
/// (`docs/design-system/colors_and_type.css`). Monochrome-plus-one: white at a
/// graded opacity ladder over true black, with one green for the checked state.
@available(macOS 13, *)
enum MGTheme {
    static let green = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255) // systemGreen dark #30D158

    static let secondary = Color.white.opacity(0.55) // time label, "Add point"
    static let iconIdle = Color.white.opacity(0.50)  // hollow circle, ×, arrows
    static let iconHover = Color.white.opacity(0.80) // hover bumps one rung
    static let dismissHover = Color.white.opacity(0.85)
    static let doneText = Color.white.opacity(0.45)
    static let strike = Color.white.opacity(0.40)
    static let pastRow = Color.white.opacity(0.45)    // read-only past rows, dimmed
    static let fieldFill = Color.white.opacity(0.08)
    static let fieldBorder = Color.white.opacity(0.10)
    static let fieldBorderFocus = Color.white.opacity(0.25)
    static let placeholder = Color.white.opacity(0.35)
    static let disabled = Color.white.opacity(0.22)

    static let sizeCaption: CGFloat = 12
    static let sizeCaption2: CGFloat = 11

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

/// One talking-point row. Behavior is gated by the entry's recency `kind`:
/// `active` → tappable check-off + remove; `upcoming` → remove only (no
/// check-off — the meeting hasn't happened); `past` → read-only, dimmed,
/// showing raised ✓ / missed ○ (origin R5, R7, R8, R12).
@available(macOS 13, *)
private struct PointRowView: View {
    let point: Point
    let kind: ReviewKind
    let onToggle: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private var isPast: Bool { kind == .past }
    private var canCheck: Bool { kind == .active }
    private var canRemove: Bool { kind == .active || kind == .upcoming }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { if canCheck { onToggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: point.checked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(iconColor)
                        .scaleEffect(point.checked ? 1.06 : 1.0)
                        .animation(.easeOut(duration: MGTheme.tickDuration), value: point.checked)
                    Text(point.text)
                        .font(.system(size: MGTheme.sizeCaption, weight: .medium))
                        .foregroundStyle(textColor)
                        .strikethrough(point.checked, color: MGTheme.strike)
                        .lineLimit(2)
                        .animation(.easeOut(duration: MGTheme.tickDuration), value: point.checked)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PeekButtonStyle())
            .disabled(!canCheck)

            if canRemove && hovering {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(MGTheme.iconIdle)
                }
                .buttonStyle(PeekButtonStyle())
                .help("Remove this point")
            }
        }
        .opacity(isPast ? 0.6 : 1.0) // read-only past rows are visibly dimmed
        .onHover { hovering = $0 }
    }

    private var iconColor: Color {
        if point.checked { return MGTheme.green }
        if isPast { return MGTheme.pastRow }
        return hovering && canCheck ? MGTheme.iconHover : MGTheme.iconIdle
    }

    private var textColor: Color {
        if point.checked { return MGTheme.doneText }
        if isPast { return MGTheme.pastRow }
        return .white
    }
}

/// The peek's contents: a recency-labelled title row, the points list with
/// per-recency gating, quick-add, prev/next browse arrows, a "now" badge, and a
/// dismiss control (origin R1–R8, R11, R12, R25; AE1–AE5).
@available(macOS 13, *)
struct PeekView: View {
    static let width: CGFloat = 360

    @ObservedObject var model: PeekModel
    @State private var draft: String = ""
    @State private var dismissHovering = false
    @State private var addHovering = false
    @FocusState private var fieldFocused: Bool

    private var showsNav: Bool { model.isBrowsing || model.canPrev || model.canNext || model.nowBadge }

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
            // ‹ prev — flush-left, only when there's an earlier entry.
            if showsNav {
                navArrow(system: "chevron.left", enabled: model.canPrev, action: model.onPrev)
                    .accessibilityLabel("Previous meeting")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(model.title)
                        .font(.system(size: MGTheme.sizeCaption2))
                        .tracking(0.1)
                        .foregroundStyle(MGTheme.secondary)
                    if showsNav { recencyLabel }
                }

                if let message = model.emptyMessage {
                    Text(message)
                        .font(.system(size: MGTheme.sizeCaption))
                        .foregroundStyle(MGTheme.secondary)
                } else {
                    ForEach(Array(model.points.enumerated()), id: \.offset) { index, point in
                        PointRowView(
                            point: point,
                            kind: model.kind,
                            onToggle: { model.onToggle(index) },
                            onRemove: { model.onRemove(index) }
                        )
                    }
                    if model.kind != .past { quickAdd }
                }
            }

            Spacer(minLength: 4)

            // › next (with the "now" badge) then × dismiss, top-right (× outermost).
            if showsNav {
                ZStack(alignment: .topTrailing) {
                    navArrow(system: "chevron.right", enabled: model.canNext || model.nowBadge, action: model.onNext)
                        .accessibilityLabel(model.nowBadge ? "A meeting is live — jump to it" : "Next meeting")
                    if model.nowBadge {
                        Circle().fill(MGTheme.green).frame(width: 6, height: 6).offset(x: 2, y: -2)
                    }
                }
            }

            Button(action: { model.onDismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(dismissHovering ? MGTheme.dismissHover : MGTheme.iconIdle)
            }
            .buttonStyle(PeekButtonStyle())
            .onHover { dismissHovering = $0 }
            .help(model.isBrowsing ? "Close" : "Done — archive these points")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .padding(.top, model.topInset + 8)
        .frame(width: Self.width, alignment: .leading)
        .background(Color.black)
        .clipShape(peekClip)
        .animation(MGTheme.easeOut, value: model.quickAddVisible)
        .onChange(of: model.quickAddVisible) { visible in
            if visible { fieldFocused = true } else { draft = "" }
        }
    }

    @ViewBuilder
    private var recencyLabel: some View {
        let text: String = model.kind == .past ? "Past" : (model.kind == .upcoming ? "Upcoming" : "Now")
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(model.kind == .active ? MGTheme.green : MGTheme.secondary)
    }

    private func navArrow(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? MGTheme.iconIdle : MGTheme.disabled)
                .frame(width: 22, height: 22) // ≥ comfortable target on the strip
                .contentShape(Rectangle())
        }
        .buttonStyle(PeekButtonStyle())
        .disabled(!enabled)
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
                    .accessibilityLabel("Add a point…")
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
                model.onQuickAddBegin()
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
