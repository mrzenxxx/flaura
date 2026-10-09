import AppKit
import AuraCore
import SwiftUI

extension RGB {
    var color: Color {
        Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b))
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Float(ns.redComponent), Float(ns.greenComponent), Float(ns.blueComponent))
    }
}

extension Palette {
    var gradient: LinearGradient {
        let stops = colors.count == 1 ? [colors[0], colors[0]] : colors
        return LinearGradient(colors: stops.map(\.color), startPoint: .leading, endPoint: .trailing)
    }
}

extension DeviceKind {
    var symbol: String {
        switch self {
        case .keyboard: "keyboard"
        case .mouse: "computermouse"
        case .mousepad: "rectangle.dashed"
        case .headset: "headphones"
        case .strip: "lightbulb.led"
        case .other: "lightbulb"
        }
    }
}

/// Small caps section title used throughout the panel.
struct SectionTitle: View {
    let text: String
    var trailing: AnyView?

    init(_ text: String, trailing: AnyView? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
    }
}

/// A slider that only commits when the drag ends, so effects are not rebuilt on every tick.
struct CommitSlider: View {
    let title: String
    let value: Float
    let commit: (Float) -> Void
    var format: (Float) -> String = { "\(Int(($0 * 100).rounded()))%" }

    @State private var draft: Float?

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 112, alignment: .leading)
            Slider(
                value: Binding(get: { Double(draft ?? value) }, set: { draft = Float($0) }),
                in: 0...1
            ) { editing in
                if !editing, let draft {
                    commit(draft)
                    self.draft = nil
                }
            }
            .controlSize(.small)
            Text(format(draft ?? value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// One effect in the picker grid.
struct EffectTile: View {
    let kind: EffectKind
    let selected: Bool
    let palette: Palette
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 18)
                    .foregroundStyle(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(.primary))
                Text(kind.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(palette.gradient.opacity(0.22))
                                   : AnyShapeStyle(Color.primary.opacity(hovering ? 0.09 : 0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(kind.subtitle)
    }
}

/// A palette preset as a round gradient swatch.
struct PaletteSwatch: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AngularGradient(colors: (palette.colors + [palette.colors[0]]).map(\.color), center: .center))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 1))
                .padding(2)
        }
        .buttonStyle(.plain)
        .help(palette.name)
    }
}

/// Status chip for a connected device.
struct DeviceChip: View {
    let info: DeviceInfo
    let health: DeviceHealth?
    let enabled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: info.kind.symbol)
                .font(.system(size: 11))
            Text(info.name.replacingOccurrences(of: "Razer ", with: ""))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .opacity(enabled ? 1 : 0.5)
        .help(helpText)
    }

    private var statusColor: Color {
        if case .failing = health { return .orange }
        return enabled ? .green : .secondary
    }

    private var helpText: String {
        if case .failing(let message) = health { return "\(info.detail)\nОшибка: \(message)" }
        return info.detail
    }
}
