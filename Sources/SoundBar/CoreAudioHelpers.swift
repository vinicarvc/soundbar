import CoreAudio
import AudioToolbox
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32

    var symbol: String {
        switch transport {
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeUSB: return "hifispeaker"
        default: return "speaker.wave.2"
        }
    }
}

/// Wrappers finos sobre a API C do Core Audio.
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let virtualMainVolume: AudioObjectPropertySelector = 0x766D7663 // 'vmvc'

    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    static func has(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> Bool {
        var a = addr(sel, scope)
        return AudioObjectHasProperty(obj, &a)
    }

    static func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, as: T.Type = T.self) -> T? {
        var a = addr(sel, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let ptr = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, ptr) == noErr else { return nil }
        return ptr.pointee
    }

    @discardableResult
    static func set<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, value: T) -> OSStatus {
        var a = addr(sel, scope)
        var v = value
        return AudioObjectSetPropertyData(obj, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var s: Unmanaged<CFString>?
        let st = withUnsafeMutablePointer(to: &s) { AudioObjectGetPropertyData(obj, &a, 0, nil, &size, $0) }
        guard st == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }

    static func array<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [T] {
        var a = addr(sel, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let n = Int(size) / MemoryLayout<T>.stride
        return [T](unsafeUninitializedCapacity: n) { buf, count in
            var sz = size
            let st = AudioObjectGetPropertyData(obj, &a, 0, nil, &sz, buf.baseAddress!)
            count = st == noErr ? Int(sz) / MemoryLayout<T>.stride : 0
        }
    }

    // MARK: Dispositivos

    static func hasOutput(_ dev: AudioObjectID) -> Bool {
        var a = addr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr && size > 0
    }

    static func outputDevices() -> [AudioDevice] {
        let ids: [AudioObjectID] = array(system, kAudioHardwarePropertyDevices)
        return ids.compactMap { id in
            guard hasOutput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            let transport: UInt32 = get(id, kAudioDevicePropertyTransportType) ?? 0
            return AudioDevice(id: id, uid: uid, name: name, transport: transport)
        }
    }

    static func defaultOutput() -> AudioObjectID {
        get(system, kAudioHardwarePropertyDefaultOutputDevice) ?? AudioObjectID(kAudioObjectUnknown)
    }
    static func defaultSystemOutput() -> AudioObjectID {
        get(system, kAudioHardwarePropertyDefaultSystemOutputDevice) ?? AudioObjectID(kAudioObjectUnknown)
    }
    static func setDefaultOutput(_ id: AudioObjectID) {
        set(system, kAudioHardwarePropertyDefaultOutputDevice, value: id)
    }
    static func setDefaultSystemOutput(_ id: AudioObjectID) {
        set(system, kAudioHardwarePropertyDefaultSystemOutputDevice, value: id)
    }

    static func volume(_ dev: AudioObjectID) -> Float? {
        get(dev, virtualMainVolume, scope: kAudioObjectPropertyScopeOutput)
    }
    static func setVolume(_ dev: AudioObjectID, _ v: Float) {
        set(dev, virtualMainVolume, scope: kAudioObjectPropertyScopeOutput, value: v)
    }
    static func muted(_ dev: AudioObjectID) -> Bool? {
        let v: UInt32? = get(dev, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return v.map { $0 != 0 }
    }
    static func setMuted(_ dev: AudioObjectID, _ m: Bool) {
        set(dev, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, value: UInt32(m ? 1 : 0))
    }
}
