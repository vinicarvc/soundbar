import CoreAudio
import AudioToolbox
import Foundation

/// Controla o volume / saída de UM app usando um Core Audio process tap (macOS 14.2+).
///
/// Fluxo: tap nos processos do app (mudo no destino original) -> dispositivo agregado privado
/// (tap + dispositivo de saída escolhido) -> IOProc copia o áudio do tap para a saída multiplicado pelo ganho.
final class AppTap {
    private(set) var processObjects: Set<AudioObjectID>
    let outputUID: String

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// [0] = ganho alvo, [1] = ganho atual (rampa no callback de áudio)
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 2)
    private let queue = DispatchQueue(label: "soundbar.tap", qos: .userInteractive)

    var volume: Float {
        get { gain[0] }
        set { gain[0] = newValue }
    }

    init(processObjects: Set<AudioObjectID>, outputUID: String, volume: Float) {
        self.processObjects = processObjects
        self.outputUID = outputUID
        gain[0] = volume
        gain[1] = volume
    }

    deinit {
        stop()
        gain.deallocate()
    }

    /// Retorna nil em caso de sucesso, ou uma mensagem de erro.
    func start() -> String? {
        let desc = CATapDescription(stereoMixdownOfProcesses: Array(processObjects))
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true

        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            return "Não foi possível criar o tap (erro \(st)). Permita a captura de áudio em Ajustes > Privacidade."
        }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SoundBar-\(desc.uuid.uuidString.prefix(6))",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard st == noErr else {
            aggID = AudioObjectID(kAudioObjectUnknown)
            stop()
            return "Não foi possível criar o dispositivo agregado (erro \(st))."
        }

        let g = gain
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { _, inData, _, outData, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let outs = UnsafeMutableAudioBufferListPointer(outData)
            guard ins.count > 0, outs.count > 0 else { return }

            // O tap é o último stream de entrada (sub-devices vêm antes dos taps).
            let src = ins[ins.count - 1]
            let dst = outs[0]
            guard let sp = src.mData?.assumingMemoryBound(to: Float.self),
                  let dp = dst.mData?.assumingMemoryBound(to: Float.self) else { return }

            let sCh = max(Int(src.mNumberChannels), 1)
            let dCh = max(Int(dst.mNumberChannels), 1)
            let frames = min(Int(src.mDataByteSize) / (4 * sCh), Int(dst.mDataByteSize) / (4 * dCh))
            let target = g[0]
            var cur = g[1]
            let step = frames > 0 ? (target - cur) / Float(frames) : 0
            for f in 0..<frames {
                cur += step
                for c in 0..<dCh {
                    dp[f * dCh + c] = sp[f * sCh + min(c, sCh - 1)] * cur
                }
            }
            g[1] = target
        }
        guard st == noErr, let procID else {
            stop()
            return "Não foi possível criar o IOProc (erro \(st))."
        }
        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else {
            stop()
            return "Não foi possível iniciar o áudio (erro \(st))."
        }
        return nil
    }

    func stop() {
        if aggID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggID, procID)
                AudioDeviceDestroyIOProcID(aggID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        procID = nil
        aggID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }
}
