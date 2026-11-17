import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            sectionTitle("Saída")
            VStack(spacing: 2) {
                ForEach(m.outputs) { dev in OutputRow(device: dev) }
            }
            Divider()
            sectionTitle("Aplicativos")
            systemSoundsRow
            if m.apps.isEmpty {
                Text("Nenhum app usando áudio")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(m.apps) { app in AppRow(app: app) }
            if let err = m.lastError {
                Text(err).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Ajustes de Som…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                }
                Spacer()
                Button("Sair") { m.stopAll(); NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Som").font(.headline)
                Spacer()
                Toggle("", isOn: Binding(get: { !m.muted }, set: { m.setMuted(!$0) }))
                    .toggleStyle(.switch).labelsHidden().disabled(!m.masterAvailable)
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(m.masterVolume) }, set: { m.setMaster(Float($0)) }), in: 0...1)
                    .disabled(!m.masterAvailable)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.callout).foregroundStyle(.secondary)
    }

    private var systemSoundsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill").frame(width: 24, height: 24).foregroundStyle(.secondary)
            Text("Sons do Sistema")
            Spacer()
            Menu {
                ForEach(m.outputs) { dev in
                    Button { m.setSystemOutput(dev) } label: {
                        if dev.id == m.systemOutputID { Label(dev.name, systemImage: "checkmark") } else { Text(dev.name) }
                    }
                }
            } label: {
                Text(m.outputs.first { $0.id == m.systemOutputID }?.name ?? "—")
                    .lineLimit(1).frame(maxWidth: 130, alignment: .trailing)
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .font(.body)
    }
}

struct OutputRow: View {
    @EnvironmentObject var m: AudioModel
    let device: AudioDevice
    private var selected: Bool { device.id == m.defaultOutputID }

    var body: some View {
        Button { m.setDefaultOutput(device) } label: {
            HStack(spacing: 10) {
                Image(systemName: device.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(selected ? Color.accentColor : Color.secondary.opacity(0.18)))
                Text(device.name).fontWeight(selected ? .medium : .regular)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AppRow: View {
    @EnvironmentObject var m: AudioModel
    let app: AppItem

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: m.icon(for: app.id)).resizable().frame(width: 24, height: 24)
                Text(app.name).lineLimit(1)
                if app.playing {
                    Image(systemName: "waveform").font(.caption2).foregroundStyle(Color.accentColor)
                }
                Spacer()
                devicePicker
            }
            HStack(spacing: 6) {
                Image(systemName: "speaker.fill").font(.caption).foregroundStyle(.secondary)
                Slider(value: Binding(get: { Double(m.setting(app.id).volume) },
                                      set: { m.setVolume(app.id, Float($0)) }), in: 0...1)
                    .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var devicePicker: some View {
        let uid = m.setting(app.id).deviceUID
        let current = m.outputs.first { $0.uid == uid }
        return Menu {
            Button { m.setDevice(app.id, uid: nil) } label: {
                if current == nil { Label("Padrão do Sistema", systemImage: "checkmark") } else { Text("Padrão do Sistema") }
            }
            Divider()
            ForEach(m.outputs) { dev in
                Button { m.setDevice(app.id, uid: dev.uid) } label: {
                    if dev.uid == uid { Label(dev.name, systemImage: "checkmark") } else { Text(dev.name) }
                }
            }
        } label: {
            Text(current?.name ?? "Padrão do Sistema").lineLimit(1).frame(maxWidth: 130, alignment: .trailing)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .font(.callout)
    }
}
