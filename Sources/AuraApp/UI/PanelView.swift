import AuraCore
import SwiftUI

/// The menu bar panel: everything needed day to day, in one scrollable column.
struct PanelView: View {
    @ObservedObject var model: AppModel
    let openSettings: () -> Void
    let quit: () -> Void

    /// Index of the palette color open in the editor.
    @State private var editingColor: Int?

    init(model: AppModel, openSettings: @escaping () -> Void, quit: @escaping () -> Void, editingColor: Int? = nil) {
        self.model = model
        self.openSettings = openSettings
        self.quit = quit
        _editingColor = State(initialValue: editingColor)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            devices
            effects
            palette
            parameters
            reactions
            footer
        }
        .padding(16)
        .frame(width: 372)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(model.settings.palette.gradient)
                Text("Flaura")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Toggle("", isOn: $model.settings.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.min").font(.system(size: 11)).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(model.settings.brightness) },
                                      set: { model.settings.brightness = Float($0) }), in: 0.05...1)
                    .controlSize(.small)
                Image(systemName: "sun.max.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var devices: some View {
        Group {
            if model.devices.isEmpty {
                Label("Устройства не найдены", systemImage: "cable.connector.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(model.devices, id: \.id) { info in
                        DeviceChip(info: info, health: model.health[info.id], enabled: model.settings.device(info.id).enabled)
                    }
                }
            }
        }
    }

    // MARK: Effects

    private var effects: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Огонь")
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EffectKind.flames) { tile($0) }
            }
            SectionTitle("Эффекты")
                .padding(.top, 2)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EffectKind.classics) { tile($0) }
            }
        }
    }

    private func tile(_ kind: EffectKind) -> some View {
        EffectTile(kind: kind, selected: model.settings.effect.kind == kind, palette: model.settings.palette) {
            model.settings.effect.kind = kind
        }
    }

    // MARK: Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Палитра · \(model.settings.palette.name)")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Palette.presets, id: \.name) { preset in
                        PaletteSwatch(palette: preset, selected: model.settings.palette.colors == preset.colors) {
                            model.settings.palette = preset
                        }
                    }
                }
            }
            let colors = model.settings.palette.colors
            HStack(spacing: 6) {
                ForEach(colors.indices, id: \.self) { index in
                    ColorSwatch(color: colors[index], selected: editingColor == index) {
                        editingColor = editingColor == index ? nil : index
                    }
                }
                if colors.count < Palette.maxColors {
                    AddColorButton(action: addColor)
                }
                Spacer()
            }
            if let index = editingColor, index < colors.count {
                ColorEditor(color: colors[index], canDelete: colors.count > 1,
                            change: { setColor($0, at: index) },
                            randomize: { setColor(randomColor(besides: index), at: index) },
                            delete: { removeColor(at: index) })
            }
            paletteStrip
            Toggle("Перетекание цветов", isOn: $model.settings.paletteFlow)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.mini)
            Text("Палитра медленно прокручивается по кругу: каждый цвет перетекает в соседний. Работает поверх любого эффекта.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.settings.paletteFlow {
                CommitSlider(title: "Скорость", value: model.settings.paletteFlowSpeed) {
                    model.settings.paletteFlowSpeed = $0
                } format: { speed in
                    var settings = AuraSettings()
                    settings.paletteFlowSpeed = speed
                    let seconds = settings.paletteFlowSecondsPerColor
                    return String(format: seconds >= 10 ? "%.0f с" : "%.1f с", seconds)
                }
                .help("Сколько секунд один цвет перетекает в соседний")
            }
        }
    }

    /// The palette as a gradient bar. With flow on it moves the way the lights do.
    @ViewBuilder
    private var paletteStrip: some View {
        let palette = model.settings.palette
        if model.settings.paletteFlow {
            let lut = PaletteLUT(palette)
            let n = palette.colors.count
            let turn = Double(model.settings.paletteFlowSecondsPerColor) * Double(n)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate / turn
                let colors = (0..<n).map { lut.loop(Float($0) / Float(n) + fraction(phase)) }
                strip(Palette(name: "", colors: colors))
            }
        } else {
            strip(palette)
        }
    }

    private func strip(_ palette: Palette) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(palette.gradient)
            .frame(height: 6)
    }

    private func fraction(_ x: Double) -> Float {
        Float(x - x.rounded(.down))
    }

    private func addColor() {
        var p = model.settings.palette
        guard p.colors.count < Palette.maxColors else { return }
        var rng = SystemRandomNumberGenerator()
        p.colors.append(Palette.randomColor(avoiding: p.colors, using: &rng))
        p.name = "Своя"
        model.settings.palette = p
        editingColor = p.colors.count - 1
    }

    private func setColor(_ color: RGB, at index: Int) {
        var p = model.settings.palette
        guard index < p.colors.count, p.colors[index] != color else { return }
        p.colors[index] = color
        p.name = "Своя"
        model.settings.palette = p
    }

    private func removeColor(at index: Int) {
        var p = model.settings.palette
        guard p.colors.count > 1, index < p.colors.count else { return }
        p.colors.remove(at: index)
        p.name = "Своя"
        model.settings.palette = p
        editingColor = nil
    }

    private func randomColor(besides index: Int) -> RGB {
        var others = model.settings.palette.colors
        if index < others.count { others.remove(at: index) }
        var rng = SystemRandomNumberGenerator()
        return Palette.randomColor(avoiding: others, using: &rng)
    }

    // MARK: Parameters

    @ViewBuilder
    private var parameters: some View {
        let kind = model.settings.effect.kind
        if kind.usesSpeed || kind.usesIntensity || kind.usesDirection || kind.usesSpan {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("\(kind.title) · \(kind.subtitle)")
                if kind.usesSpeed {
                    CommitSlider(title: "Скорость", value: model.settings.effect.speed) { model.settings.effect.speed = $0 }
                }
                if kind.usesIntensity {
                    CommitSlider(title: kind.intensityTitle, value: model.settings.effect.intensity) {
                        model.settings.effect.intensity = $0
                    }
                }
                if kind.usesDirection {
                    Picker("Направление", selection: $model.settings.effect.direction) {
                        ForEach(Direction.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .font(.system(size: 12))
                }
                HStack(spacing: 16) {
                    if kind.usesSpan {
                        Toggle("На все устройства", isOn: $model.settings.effect.spanDevices)
                            .help("Один эффект через весь стол вместо повтора на каждом устройстве")
                    }
                    if kind == .wave || kind == .wheel {
                        Toggle("Радуга", isOn: $model.settings.effect.rainbow)
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            }
        }
    }

    // MARK: Reactions

    private var reactions: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Реакции")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Toggle("Волна от клавиш", isOn: $model.settings.reactive.ripple)
                    Toggle("Вспышка клавиши", isOn: $model.settings.reactive.keyGlow)
                }
                GridRow {
                    Toggle("Импульс от клика", isOn: $model.settings.reactive.clickPulse)
                    Toggle("Клавиши раздувают огонь", isOn: $model.settings.reactive.stoke)
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            if model.settings.reactive.needsInput {
                CommitSlider(title: "Длительность", value: model.settings.reactive.duration) {
                    model.settings.reactive.duration = $0
                } format: { value in
                    var reactive = ReactiveSettings()
                    reactive.duration = value
                    return String(format: "%.1f с", reactive.seconds)
                }
                HStack {
                    Picker("Цвет реакции", selection: $model.settings.reactive.colorMode) {
                        ForEach(ReactiveColorMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .font(.system(size: 12))
                }
                if !model.inputAccess {
                    permissionBanner
                }
            }
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Чтобы подсветка реагировала на клавиши и клики, нужно разрешение «Мониторинг ввода». Flaura только слушает нажатия и никуда их не передаёт.")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Разрешить…") { model.requestInputAccess() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Настройки…", action: openSettings)
            Spacer()
            Button("Выйти", action: quit)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.top, 2)
    }
}
