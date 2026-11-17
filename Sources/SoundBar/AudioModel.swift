import AppKit
import CoreAudio
import Darwin
import SwiftUI

struct AppSetting: Codable, Equatable {
    var volume: Float = 1
    var deviceUID: String? = nil   // nil = padrão do sistema
    var isDefault: Bool { volume >= 0.999 && deviceUID == nil }
}

struct AppItem: Identifiable, Equatable {
    let id: String            // bundle id
    let name: String
    let objectIDs: Set<AudioObjectID>
    let playing: Bool
}

final class AudioModel: ObservableObject {
    @Published var outputs: [AudioDevice] = []
    @Published var defaultOutputID = AudioObjectID(kAudioObjectUnknown)
    @Published var systemOutputID = AudioObjectID(kAudioObjectUnknown)
    @Published var masterVolume: Float = 0
    @Published var masterAvailable = false
    @Published var muted = false
    @Published var apps: [AppItem] = []
    @Published var settings: [String: AppSetting] = [:]
    @Published var lastError: String?

    private var engines: [String: AppTap] = [:]
    private var icons: [String: NSImage] = [:]
    private var failedAttempt: [String: String] = [:]
    private var timer: Timer?
    private let defaultsKey = "appSettings.v1"

    var menuIcon: String { muted ? "speaker.slash.fill" : "speaker.wave.2.fill" }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode([String: AppSetting].self, from: data) {
            settings = s
        }
        for sel in [kAudioHardwarePropertyDevices,
                    kAudioHardwarePropertyDefaultOutputDevice,
                    kAudioHardwarePropertyDefaultSystemOutputDevice,
                    kAudioHardwarePropertyProcessObjectList] {
            var a = CA.addr(sel)
            AudioObjectAddPropertyListenerBlock(CA.system, &a, .main) { [weak self] _, _ in self?.refresh() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.stopAll() }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    // MARK: Atualização

    func refresh() {
        let outs = CA.outputDevices()
        if outs != outputs { outputs = outs }
        let d = CA.defaultOutput()
        if d != defaultOutputID { defaultOutputID = d }
        let s = CA.defaultSystemOutput()
        if s != systemOutputID { systemOutputID = s }

        let vol = CA.volume(d)
        masterAvailable = vol != nil
        if let vol, vol != masterVolume { masterVolume = vol }
        let m = CA.muted(d) ?? false
        if m != muted { muted = m }

        refreshApps()
        applyAll()
    }

    private func refreshApps() {
        let objs: [AudioObjectID] = CA.array(CA.system, kAudioHardwarePropertyProcessObjectList)
        var groups: [String: (app: NSRunningApplication, ids: Set<AudioObjectID>, playing: Bool)] = [:]
        for obj in objs {
            guard let pid: pid_t = CA.get(obj, kAudioProcessPropertyPID), pid != getpid(),
                  let app = Self.owningApp(of: pid) else { continue }
            let running: UInt32 = CA.get(obj, kAudioProcessPropertyIsRunningOutput) ?? 0
            let key = app.bundleIdentifier ?? "pid-\(app.processIdentifier)"
            var g = groups[key] ?? (app, [], false)
            g.ids.insert(obj)
            g.playing = g.playing || running != 0
            groups[key] = g
        }
        let items = groups.map { key, g in
            if icons[key] == nil { icons[key] = g.app.icon }
            return AppItem(id: key, name: g.app.localizedName ?? key, objectIDs: g.ids, playing: g.playing)
        }.sorted { ($0.playing ? 0 : 1, $0.name.lowercased()) < ($1.playing ? 0 : 1, $1.name.lowercased()) }
        if items != apps { apps = items }
    }

    func icon(for id: String) -> NSImage { icons[id] ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)! }

    /// Resolve o app "dono" de um processo auxiliar (ex.: Chrome Helper -> Google Chrome).
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let h = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(h, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func parentPID(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let n = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        return n > 0 ? pid_t(info.pbi_ppid) : nil
    }

    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        if let a = NSRunningApplication(processIdentifier: pid), a.activationPolicy == .regular { return a }
        if let r = responsiblePID?(pid), r > 1,
           let a = NSRunningApplication(processIdentifier: r), a.activationPolicy == .regular { return a }
        var p = pid
        for _ in 0..<8 {
            guard let pp = parentPID(p), pp > 1 else { break }
            if let a = NSRunningApplication(processIdentifier: pp), a.activationPolicy == .regular { return a }
            p = pp
        }
        return nil
    }

    // MARK: Ações – saída e volume geral

    func setDefaultOutput(_ dev: AudioDevice) { CA.setDefaultOutput(dev.id); refresh() }
    func setSystemOutput(_ dev: AudioDevice) { CA.setDefaultSystemOutput(dev.id); refresh() }

    func setMaster(_ v: Float) {
        masterVolume = v
        CA.setVolume(defaultOutputID, v)
        if v > 0, muted { setMuted(false) }
    }
    func setMuted(_ m: Bool) { muted = m; CA.setMuted(defaultOutputID, m) }

    // MARK: Ações – por app

    func setting(_ id: String) -> AppSetting { settings[id] ?? AppSetting() }

    func setVolume(_ id: String, _ v: Float) {
        var s = setting(id); s.volume = v; update(id, s)
    }
    func setDevice(_ id: String, uid: String?) {
        var s = setting(id); s.deviceUID = uid; update(id, s)
    }
    private func update(_ id: String, _ s: AppSetting) {
        if s.isDefault { settings.removeValue(forKey: id) } else { settings[id] = s }
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        failedAttempt[id] = nil   // ação do usuário libera nova tentativa
        apply(id)
    }

    // MARK: Engines

    private func resolvedUID(_ s: AppSetting) -> String? {
        if let uid = s.deviceUID, outputs.contains(where: { $0.uid == uid }) { return uid }
        return outputs.first(where: { $0.id == defaultOutputID })?.uid
    }

    private func applyAll() {
        let ids = Set(apps.map(\.id))
        for id in engines.keys where !ids.contains(id) { engines[id]?.stop(); engines[id] = nil }
        for id in ids { apply(id) }
    }

    private func apply(_ id: String) {
        guard let item = apps.first(where: { $0.id == id }) else { return }
        let s = setting(id)
        guard !s.isDefault, let uid = resolvedUID(s) else {
            engines[id]?.stop(); engines[id] = nil
            return
        }
        if let e = engines[id] {
            if e.processObjects == item.objectIDs && e.outputUID == uid { e.volume = s.volume; return }
            e.stop(); engines[id] = nil
        }
        // Evita repetir tentativas (e prompts de permissão) a cada segundo depois de uma falha.
        let attempt = "\(id)|\(uid)|\(item.objectIDs.sorted())"
        if failedAttempt[id] == attempt { return }
        let e = AppTap(processObjects: item.objectIDs, outputUID: uid, volume: s.volume)
        if let err = e.start() {
            failedAttempt[id] = attempt
            lastError = err
        } else {
            failedAttempt[id] = nil
            lastError = nil
            engines[id] = e
        }
    }

    func stopAll() {
        engines.values.forEach { $0.stop() }
        engines.removeAll()
    }
}
