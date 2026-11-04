import SwiftUI
import AVFoundation
import AudioToolbox

enum SoundMode { case off, whistle, sos }

/// SOS kalıbı: (yanık mı, süre birimi). Bir birim = 0,2 sn. ··· −−− ···
enum SOSPattern {
    static let unit = 0.2
    static let steps: [(Bool, Double)] = {
        var s: [(Bool, Double)] = []
        func dot() { s.append((true, 1)); s.append((false, 1)) }
        func dash() { s.append((true, 3)); s.append((false, 1)) }
        for _ in 0..<3 { dot() }
        s.append((false, 2))
        for _ in 0..<3 { dash() }
        s.append((false, 2))
        for _ in 0..<3 { dot() }
        s.append((false, 7))
        return s
    }()
    static let cycle: Double = steps.reduce(0) { $0 + $1.1 } * unit

    static func isOn(at t: Double) -> Bool {
        var u = t.truncatingRemainder(dividingBy: cycle) / unit
        for (on, d) in steps {
            if u < d { return on }
            u -= d
        }
        return false
    }
}

final class SirenEngine {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private let sr = 44100.0
    var mode: SoundMode = .off
    private var phase = 0.0
    private var t = 0.0

    init() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let n = AVAudioSourceNode { [weak self] _, _, frames, abl -> OSStatus in
            guard let self = self else { return noErr }
            let list = UnsafeMutableAudioBufferListPointer(abl)
            for i in 0..<Int(frames) {
                var v: Float = 0
                switch self.mode {
                case .off:
                    v = 0
                case .whistle:
                    self.t += 1 / self.sr
                    let f = (Int(self.t / 0.11) % 2 == 0) ? 2700.0 : 3300.0
                    self.phase += 2 * .pi * f / self.sr
                    v = Float(sin(self.phase)) * 0.95
                case .sos:
                    self.t += 1 / self.sr
                    self.phase += 2 * .pi * 2900.0 / self.sr
                    v = SOSPattern.isOn(at: self.t) ? Float(sin(self.phase)) * 0.95 : 0
                }
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                for b in list {
                    if let p = b.mData?.assumingMemoryBound(to: Float.self) { p[i] = v }
                }
            }
            return noErr
        }
        node = n
        engine.attach(n)
        engine.connect(n, to: engine.mainMixerNode, format: fmt)
    }

    func set(_ m: SoundMode) {
        mode = m
        t = 0
        if m == .off {
            engine.pause()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try? engine.start() }
        }
    }
}

@MainActor
final class EmergencyController: ObservableObject {
    @Published var sound: SoundMode = .off
    @Published var flash = false
    @Published var vibrate = false
    private let siren = SirenEngine()
    private var flashTask: Task<Void, Never>?
    private var vibTask: Task<Void, Never>?

    var anyActive: Bool { sound != .off || flash || vibrate }

    func setSound(_ m: SoundMode) {
        sound = (sound == m) ? .off : m
        siren.set(sound)
        idle()
    }

    func toggleFlash() {
        flash.toggle()
        flashTask?.cancel()
        if flash {
            flashTask = Task { @MainActor in
                while !Task.isCancelled {
                    for (on, d) in SOSPattern.steps {
                        if Task.isCancelled { break }
                        self.torch(on)
                        try? await Task.sleep(nanoseconds: UInt64(d * SOSPattern.unit * 1_000_000_000))
                    }
                }
                self.torch(false)
            }
        } else {
            torch(false)
        }
        idle()
    }

    func toggleVibrate() {
        vibrate.toggle()
        vibTask?.cancel()
        if vibrate {
            vibTask = Task { @MainActor in
                while !Task.isCancelled {
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                }
            }
        }
        idle()
    }

    func stopAll() {
        sound = .off; siren.set(.off)
        flash = false; flashTask?.cancel(); torch(false)
        vibrate = false; vibTask?.cancel()
        idle()
    }

    private func idle() { UIApplication.shared.isIdleTimerDisabled = anyActive }

    private func torch(_ on: Bool) {
        guard let d = AVCaptureDevice.default(for: .video), d.hasTorch else { return }
        do {
            try d.lockForConfiguration()
            if on { try d.setTorchModeOn(level: 1.0) } else { d.torchMode = .off }
            d.unlockForConfiguration()
        } catch {}
    }
}

struct EmergencyView: View {
    @StateObject private var ctl = EmergencyController()

    var body: some View {
        VStack(spacing: 14) {
            Text("ACİL MOD").font(.largeTitle.bold()).foregroundColor(.red)
            Text("Enkaz altındaysan ya da yardım çağırmak istiyorsan aç. Sesi sonuna kadar yükselt.")
                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)

            big("Düdük", "speaker.wave.3.fill", ctl.sound == .whistle) { ctl.setSound(.whistle) }
            big("SOS sesi", "dot.radiowaves.left.and.right", ctl.sound == .sos) { ctl.setSound(.sos) }
            big("Flaş SOS", "flashlight.on.fill", ctl.flash) { ctl.toggleFlash() }
            big("Titreşim", "iphone.radiowaves.left.and.right", ctl.vibrate) { ctl.toggleVibrate() }

            Button { ctl.stopAll() } label: {
                Text("HEPSİNİ DURDUR").font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.bordered)
            .tint(.gray)

            Link(destination: URL(string: "tel://112")!) {
                Label("112'yi ara", systemImage: "phone.fill").font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func big(_ title: String, _ icon: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).font(.title2)
                Text(on ? "\(title) — AÇIK" : title).font(.title3.bold())
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal)
            .frame(maxWidth: .infinity)
            .background(on ? Color.red : Color(.secondarySystemBackground))
            .foregroundColor(on ? .white : .primary)
            .cornerRadius(14)
        }
    }
}
