import AuraCore
import SwiftUI

/// The settings window: per-device options, general behaviour, permissions.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            DevicesTab(model: model)
                .tabItem { Label("Устройства", systemImage: "keyboard") }
            GeneralTab(model: model)
                .tabItem { Label("Общие", systemImage: "gearshape") }
            PermissionsTab(model: model)
                .tabItem { Label("Разрешения", systemImage: "lock.shield") }
        }
        .padding(20)
        .frame(width: 560, height: 440)
        .onAppear { model.refreshPermissions() }
    }
}

private struct DevicesTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.devices.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "cable.connector.slash").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Поддерживаемые устройства не подключены").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(model.devices, id: \.id) { info in
                        DeviceRow(model: model, info: info)
                    }
                    Text("Палитра общая для всех устройств. Своё значение для устройства можно задать для эффекта и яркости.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct DeviceRow: View {
    @ObservedObject var model: AppModel
    let info: DeviceInfo

    var body: some View {
        let device = model.settings.device(info.id)
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: info.kind.symbol)
                        .font(.system(size: 16))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name).font(.system(size: 13, weight: .semibold))
                        Text(info.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if case .failing(let message) = model.health[info.id] {
                        Label("Ошибка связи", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 11))
                            .help(message)
                    }
                    Toggle("", isOn: Binding(get: { device.enabled },
                                             set: { value in model.updateDevice(info.id) { $0.enabled = value } }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                CommitSlider(title: "Яркость", value: device.gain) { value in
                    model.updateDevice(info.id) { $0.gain = value }
                }
                Picker("Эффект", selection: Binding(
                    get: { device.effect?.kind },
                    set: { kind in
                        model.updateDevice(info.id) { settings in
                            if let kind {
                                var own = settings.effect ?? model.settings.effect
                                own.kind = kind
                                settings.effect = own
                            } else {
                                settings.effect = nil
                            }
                        }
                    }
                )) {
                    Text("Как у сцены").tag(EffectKind?.none)
                    Divider()
                    ForEach(EffectKind.flames + EffectKind.classics) { kind in
                        Text(kind.isFlame ? "Огонь · \(kind.title)" : kind.title).tag(EffectKind?.some(kind))
                    }
                }
                .font(.system(size: 12))
            }
            .padding(6)
        }
    }
}

private struct GeneralTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let error = model.loginItemError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                Toggle("Гасить подсветку, когда монитор выключается", isOn: $model.settings.dimWhenIdle)
                    .help("На экране блокировки и форме входа подсветка горит, пока горит монитор")
                Picker("После выхода из Flaura", selection: $model.settings.shutdownBehaviour) {
                    ForEach(ShutdownBehaviour.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                Picker("Частота кадров", selection: $model.settings.framesPerSecond) {
                    ForEach([20, 30, 45, 60], id: \.self) { Text("\($0) FPS").tag($0) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    CommitSlider(title: "Цветокоррекция", value: (model.settings.gamma - 1) / 1.6) { value in
                        model.settings.gamma = 1 + value * 1.6
                    } format: { String(format: "γ %.1f", 1 + $0 * 1.6) }
                    Text("Светодиоды светят линейно. Гамма около 1.8 делает тёмные цвета и плавные затухания похожими на то, что видно на экране.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("30 FPS достаточно для плавного огня. Выше — больше трафика по USB, но заметно только на быстрых эффектах.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    Image(systemName: model.inputAccess ? "checkmark.seal.fill" : "hand.raised.fill")
                        .foregroundStyle(model.inputAccess ? .green : .orange)
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Мониторинг ввода").font(.system(size: 13, weight: .semibold))
                        Text("Нужен только для реакций на клавиши и клики (волна, вспышка, «раздувание» огня). Flaura слушает события, ничего не перехватывает и никуда не передаёт. Подсветке как таковой разрешения не нужны.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if !model.inputAccess {
                        Button("Разрешить…") { model.requestInputAccess() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
