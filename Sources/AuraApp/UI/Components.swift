import AppKit
import AuraCore
import SwiftUI

extension RGB {
    var color: Color {
        Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b))
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
    @State private var dragging = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12))
                .frame(width: 112, alignment: .leading)
            Slider(
                value: Binding(get: { Double(draft ?? value) }, set: { newValue in
                    // Mouse drags commit on release; keyboard and VoiceOver steps commit at once.
                    if dragging { draft = Float(newValue) } else { commit(Float(newValue)) }
                }),
                in: 0...1
            ) { editing in
                dragging = editing
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

/// One color of the current palette; clicking it opens the color editor below the row.
struct ColorSwatch: View {
    let color: RGB
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color.color)
                .frame(width: 26, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Изменить цвет \(color.hex)")
    }
}

/// Adds a color to the palette. Sized like a swatch so it is easy to hit.
struct AddColorButton: View {
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.5 : 0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Добавить случайный цвет")
    }
}

/// Edits one palette color in place: hue, saturation and brightness bars, a hex field,
/// a random roll and delete. Keeps its own HSB so hue survives a trip through gray.
struct ColorEditor: View {
    let color: RGB
    let canDelete: Bool
    let change: (RGB) -> Void
    let randomize: () -> Void
    let delete: () -> Void

    @State private var hue: Float = 0
    @State private var saturation: Float = 1
    @State private var brightness: Float = 1
    @State private var hex = ""

    private var edited: RGB { RGB.hsv(hue, saturation, brightness) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChannelBar(title: "Тон", value: channel($hue),
                       colors: stride(from: 0, through: 6, by: 1).map { RGB.hsv(Float($0) / 6, 1, 1) })
            ChannelBar(title: "Насыщенность", value: channel($saturation),
                       colors: [RGB.hsv(hue, 0, brightness), RGB.hsv(hue, 1, brightness)])
            ChannelBar(title: "Яркость", value: channel($brightness),
                       colors: [.black, RGB.hsv(hue, saturation, 1)])
            HStack(spacing: 10) {
                TextField("#RRGGBB", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11).monospaced())
                    .frame(width: 80)
                    .onSubmit(applyHex)
                Button(action: randomize) { Label("Случайный", systemImage: "dice") }
                Spacer()
                // Tinted by hand: with `role: .destructive` this borderless button ignored clicks.
                Button(action: delete) { Label("Удалить", systemImage: "trash") }
                    .foregroundStyle(canDelete ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tertiary))
                    .disabled(!canDelete)
                    .help(canDelete ? "Убрать цвет из палитры" : "В палитре должен остаться хотя бы один цвет")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .onAppear(perform: sync)
        .onChange(of: color) {
            // A preset, the random roll or the hex field changed the color from outside the bars.
            if color != edited { sync() }
        }
    }

    private func channel(_ state: Binding<Float>) -> Binding<Float> {
        Binding(get: { state.wrappedValue }, set: { value in
            state.wrappedValue = value
            hex = edited.hex
            change(edited)
        })
    }

    private func sync() {
        let (h, s, v) = color.hsvComponents
        // Gray has no hue and black no saturation: keep what the bars had.
        if s > 0.001 && v > 0.001 { hue = h }
        if v > 0.001 { saturation = s }
        brightness = v
        hex = color.hex
    }

    private func applyHex() {
        if let parsed = RGB(hex: hex) {
            change(parsed)
        } else {
            hex = color.hex
        }
    }
}

/// A titled 0…1 slider whose track is a color gradient.
struct ChannelBar: View {
    let title: String
    @Binding var value: Float
    let colors: [RGB]

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            GradientSlider(title: title, value: $value, colors: colors)
                .frame(height: 16)
        }
    }
}

/// An `NSSlider` with a gradient bar. AppKit-backed rather than a SwiftUI drag gesture, so it
/// tracks the mouse, keyboard and VoiceOver exactly like the other sliders in the panel.
struct GradientSlider: NSViewRepresentable {
    let title: String
    @Binding var value: Float
    let colors: [RGB]

    func makeNSView(context: Context) -> NSSlider {
        let slider = GradientNSSlider(value: Double(value), minValue: 0, maxValue: 1,
                                      target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if Float(slider.doubleValue) != value { slider.doubleValue = Double(value) }
        slider.setAccessibilityLabel(title)
        if let cell = slider.cell as? GradientSliderCell {
            let stops = colors.map { NSColor(srgbRed: CGFloat($0.r), green: CGFloat($0.g), blue: CGFloat($0.b), alpha: 1) }
            if cell.colors != stops {
                cell.colors = stops
                slider.needsDisplay = true
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Float>

        init(value: Binding<Float>) { self.value = value }

        @objc func changed(_ sender: NSSlider) {
            value.wrappedValue = Float(sender.doubleValue)
        }
    }
}

private final class GradientNSSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { GradientSliderCell.self }
        set {}
    }
}

private final class GradientSliderCell: NSSliderCell {
    var colors: [NSColor] = [.black, .white]

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let height: CGFloat = 8
        let bar = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        let path = NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2)
        NSGradient(colors: colors.count > 1 ? colors : colors + colors)?.draw(in: path, angle: 0)
        NSColor.labelColor.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 0.5
        path.stroke()
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
