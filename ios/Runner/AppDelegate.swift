import ActivityKit
import AlarmKit
import AppIntents
import AVFoundation
import CryptoKit
import Flutter
import SwiftUI
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AlarmBridge") {
      AlarmBridge.register(with: registrar)
    }
  }
}

// MARK: - AlarmKit pieces

/// Extra data stored with each alarm.
struct RingMeta: AlarmMetadata {
  var ringId: String
}

/// "Full Song" button on the alarm: stops the alarm, opens WakeWave and
/// tells the Flutter side which ring it was (see `consumeFired`).
struct PlayFullSongIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Full Song"
  static var openAppWhenRun: Bool = true

  @Parameter(title: "Ring") var ringId: String
  @Parameter(title: "Alarm") var alarmId: String

  init() {}

  init(ringId: String, alarmId: UUID) {
    self.ringId = ringId
    self.alarmId = alarmId.uuidString
  }

  func perform() async throws -> some IntentResult {
    if let id = UUID(uuidString: alarmId) {
      try? AlarmManager.shared.stop(id: id)
    }
    UserDefaults.standard.set(ringId, forKey: AlarmBridge.firedKey)
    return .result()
  }
}

// MARK: - Flutter channel

/// Native side of lib/native.dart.
class AlarmBridge: NSObject, FlutterPlugin {
  static let firedKey = "alarm101.fired"
  private var player: AVAudioPlayer?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "alarm101/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AlarmBridge(), channel: channel)
  }

  private static var soundsDir: URL {
    let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    return lib.appendingPathComponent("Sounds", isDirectory: true)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "paths":
      let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      result(["docs": docs.path])

    case "requestPermission":
      Task {
        let state = try? await AlarmManager.shared.requestAuthorization()
        result(state == .authorized)
      }

    case "status":
      NSLog("alarm101: auth=\(AlarmManager.shared.authorizationState) scheduled=\((try? AlarmManager.shared.alarms.count) ?? -1)")
      result(["alarms": AlarmManager.shared.authorizationState == .authorized])

    case "analyze":
      let src = args["path"] as? String ?? ""
      DispatchQueue.global(qos: .userInitiated).async {
        let r = try? Energy.analyze(url: URL(fileURLWithPath: src))
        DispatchQueue.main.async {
          result(r.map { ["score": $0.score, "hook": $0.hook] })
        }
      }

    case "prepareSound":
      let src = args["src"] as? String ?? ""
      let name = (args["name"] as? String ?? "alarm") + ".caf"
      let hook = args["hook"] as? Double ?? 0
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Self.makeAlarmClip(src: URL(fileURLWithPath: src), name: name, hook: hook)
          DispatchQueue.main.async { result(name) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "sound", message: "\(error)", details: nil))
          }
        }
      }

    case "cleanSounds":
      let keep = Set(args["keep"] as? [String] ?? [])
      let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.soundsDir.path)) ?? []
      for f in files where f.hasPrefix("a101_") && !keep.contains(f) {
        try? FileManager.default.removeItem(at: Self.soundsDir.appendingPathComponent(f))
      }
      result(nil)

    case "syncAlarms":
      let items = args["items"] as? [[String: Any]] ?? []
      Task {
        do {
          try await Self.syncAlarms(items)
          result(nil)
        } catch {
          NSLog("alarm101: schedule failed \(error)")
          result(FlutterError(code: "alarm", message: "\(error)", details: nil))
        }
      }

    case "playPreview":
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        try AVAudioSession.sharedInstance().setActive(true)
        player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: args["path"] as? String ?? ""))
        player?.currentTime = args["start"] as? Double ?? 0
        player?.play()
        result(nil)
      } catch {
        result(FlutterError(code: "play", message: "\(error)", details: nil))
      }

    case "stopPreview":
      player?.stop()
      player = nil
      result(nil)

    case "openUrl":
      guard let url = URL(string: args["url"] as? String ?? "") else { return result(false) }
      UIApplication.shared.open(url) { ok in result(ok) }

    case "consumeFired":
      let id = UserDefaults.standard.string(forKey: Self.firedKey)
      UserDefaults.standard.removeObject(forKey: Self.firedKey)
      result(id)

    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Stable alarm UUID per ring + sound, so unchanged rings are left alone.
  private static func uuid(for key: String) -> UUID {
    var bytes = Array(Insecure.MD5.hash(data: Data(key.utf8)))
    bytes[6] = (bytes[6] & 0x0F) | 0x30
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                       bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
  }

  /// Makes AlarmKit hold exactly `items`: one fixed-date alarm per ring.
  private static func syncAlarms(_ items: [[String: Any]]) async throws {
    let manager = AlarmManager.shared
    var wanted: [UUID: [String: Any]] = [:]
    for item in items {
      let ringId = item["id"] as? String ?? ""
      let sound = item["sound"] as? String ?? ""
      wanted[uuid(for: "\(ringId)|\(sound)")] = item
    }

    let existing = (try? manager.alarms) ?? []
    for alarm in existing where wanted[alarm.id] == nil && alarm.state != .alerting {
      try? manager.cancel(id: alarm.id)
    }
    let have = Set(existing.map(\.id))

    for (id, item) in wanted where !have.contains(id) {
      let ringId = item["id"] as? String ?? ""
      let at = Date(timeIntervalSince1970: (item["at"] as? Double ?? 0) / 1000)
      if at <= Date() { continue }
      let title = item["title"] as? String ?? "Wake up"
      let sound = item["sound"] as? String ?? ""

      let alert = AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: "🎵 \(title)"),
        stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
        secondaryButton: AlarmButton(text: "Full Song", textColor: .white, systemImageName: "music.note"),
        secondaryButtonBehavior: .custom
      )
      let attributes = AlarmAttributes<RingMeta>(
        presentation: AlarmPresentation(alert: alert),
        metadata: RingMeta(ringId: ringId),
        tintColor: Color(red: 1, green: 0.48, blue: 0.09)
      )
      let config = AlarmManager.AlarmConfiguration<RingMeta>(
        schedule: .fixed(at),
        attributes: attributes,
        secondaryIntent: PlayFullSongIntent(ringId: ringId, alarmId: id),
        sound: sound.isEmpty ? .default : .named(sound)
      )
      _ = try await manager.schedule(id: id, configuration: config)
      NSLog("alarm101: scheduled \(ringId) at \(at) sound=\(sound)")
    }
  }

  /// Converts a downloaded preview into a < 30 s CAF in Library/Sounds
  /// (the length/format limit for custom alert sounds). The clip starts at
  /// `hook` seconds (the punchiest part) and wraps around to the start of the
  /// preview with a short crossfade, so the alarm opens on the beat.
  private static func makeAlarmClip(src: URL, name: String, hook: Double) throws {
    try FileManager.default.createDirectory(at: soundsDir, withIntermediateDirectories: true)
    let dst = soundsDir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: dst.path) { return }

    let input = try AVAudioFile(forReading: src)
    let format = input.processingFormat
    let rate = format.sampleRate
    let channels = Int(format.channelCount)
    guard let all = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)) else { return }
    try input.read(into: all)
    let len = Int(all.frameLength)
    guard len > 0, let data = all.floatChannelData else { return }

    let start = min(max(0, Int(hook * rate)), max(0, len - Int(8 * rate)))
    let xf = Int(0.4 * rate)
    let total = min(len, Int(29.0 * rate))
    let fadeIn = Int(0.15 * rate)
    let fadeOut = Int(1.5 * rate)

    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: rate,
      AVNumberOfChannelsKey: channels,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
    ]
    let tmp = soundsDir.appendingPathComponent(".tmp_" + name)
    try? FileManager.default.removeItem(at: tmp)
    let output = try AVAudioFile(forWriting: tmp, settings: settings,
                                 commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
          let o = out.floatChannelData else { return }
    out.frameLength = AVAudioFrameCount(total)

    let tail = len - start  // frames from the hook to the end of the preview
    for c in 0..<channels {
      let x = data[c]
      for i in 0..<total {
        var v: Float
        if start == 0 || i < tail - xf {
          v = x[(start + i) % len]
        } else if i < tail {
          // Crossfade the preview's end into its beginning.
          let k = Float(i - (tail - xf)) / Float(xf)
          v = x[start + i] * (1 - k) + x[i - (tail - xf)] * k
        } else {
          v = x[(i - tail + xf) % len]
        }
        var g: Float = 1
        if i < fadeIn { g = Float(i) / Float(fadeIn) }
        if i > total - fadeOut { g = min(g, Float(total - i) / Float(fadeOut)) }
        o[c][i] = v * g
      }
    }
    try output.write(from: out)
    try FileManager.default.moveItem(at: tmp, to: dst)
  }
}

/// How danceable/upbeat a preview sounds, plus where its punchiest part starts.
/// Same maths as Energy.kt on Android; tuned on known party vs romantic songs
/// (party ≈ 2.9–3.6, romantic ≈ 0.5–1.9).
enum Energy {
  struct Result { let score: Double; let hook: Double }

  static func analyze(url: URL) throws -> Result {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
      return Result(score: 0, hook: 0)
    }
    try file.read(into: buf)
    let n = Int(buf.frameLength)
    guard let ch = buf.floatChannelData, n > 0 else { return Result(score: 0, hook: 0) }
    let channels = Int(format.channelCount)
    var mono = [Float](repeating: 0, count: n)
    for c in 0..<channels {
      for i in 0..<n { mono[i] += ch[c][i] / Float(channels) }
    }
    return analyze(mono: mono, rate: format.sampleRate)
  }

  static func analyze(mono: [Float], rate: Double) -> Result {
    let step = max(1, Int((rate / 22050).rounded()))
    let sr = rate / Double(step)
    let hop = 512
    var x = [Double]()
    x.reserveCapacity(mono.count / step + 1)
    var i = 0
    while i < mono.count { x.append(Double(mono[i])); i += step }
    let frames = x.count / hop
    if frames < 64 { return Result(score: 0, hook: 0) }

    let a = exp(-2 * Double.pi * 150 / sr)
    var lp = 0.0, prev = 0.0
    var e = [Double](repeating: 1e-10, count: frames)
    var l = e, h = e
    for f in 0..<frames {
      var se = 0.0, sl = 0.0, sh = 0.0
      for j in 0..<hop {
        let v = x[f * hop + j]
        lp = (1 - a) * v + a * lp
        let d = v - prev
        prev = v
        se += v * v; sl += lp * lp; sh += d * d
      }
      e[f] += se / Double(hop); l[f] += sl / Double(hop); h[f] += sh / Double(hop)
    }
    let db = { (v: Double) in 10 * log10(v) }
    var env = [Double](repeating: 0, count: frames - 1)
    var oL = 0.0, oH = 0.0
    for f in 1..<frames {
      let ul = max(0, db(l[f]) - db(l[f - 1]))
      let uh = max(0, db(h[f]) - db(h[f - 1]))
      oL += ul; oH += uh; env[f - 1] = ul + uh
    }
    oL /= Double(frames - 1); oH /= Double(frames - 1)
    let mean = env.reduce(0, +) / Double(env.count)
    for k in env.indices { env[k] -= mean }
    let fps = sr / Double(hop)
    let ac0 = env.reduce(0) { $0 + $1 * $1 } + 1e-9
    var beat = 0.0
    for lag in Int(0.25 * fps)..<Int(1.0 * fps) where lag < env.count {
      var s = 0.0
      for k in 0..<(env.count - lag) { s += env[k] * env[k + lag] }
      beat = max(beat, s / ac0)
    }
    let bass = db(l.reduce(0, +) / Double(frames)) - db(e.reduce(0, +) / Double(frames))
    let score = oL + oH + 1.5 * beat + 0.1 * bass

    // Hook = start of the loudest 6 s window (only if the preview has a clear build-up).
    let w = Int(6 * fps)
    var hook = 0.0
    if frames > w {
      let d = e.map(db)
      var run = d[0..<w].reduce(0, +)
      var best = run, worst = run, at = 0
      for f in w..<frames {
        run += d[f] - d[f - w]
        if run > best { best = run; at = f - w + 1 }
        worst = min(worst, run)
      }
      if (best - worst) / Double(w) >= 2 { hook = max(0, Double(at) / fps - 0.3) }
    }
    return Result(score: score, hook: hook)
  }
}
