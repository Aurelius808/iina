import Cocoa
import MetalKit
import QuartzCore

final class LilithJamView: NSView {
  private let model = LilithVisualizerModel(
    reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  )
  private let analyzer = LilithAudioAnalyzer()
  private let metalView = MTKView()
  private var renderer: LilithMetalRenderer?
  private var audioTap: LilithAudioTap?
  private var fallbackTimer: Timer?
  private weak var player: PlayerCore?

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    translatesAutoresizingMaskIntoConstraints = false
    installMetalView()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setActive(_ active: Bool) {
    isHidden = !active
    active ? start() : stop()
  }

  func advancePreset() {
    renderer?.advancePreset()
  }

  private func installMetalView() {
    metalView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(metalView)
    NSLayoutConstraint.activate([
      metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
      metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
      metalView.topAnchor.constraint(equalTo: topAnchor),
      metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    renderer = LilithMetalRenderer(mtkView: metalView, model: model)
  }

  private func start() {
    model.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if !startAudioTap() {
      startFallbackMotion()
    }
    metalView.isPaused = false
  }

  private func stop() {
    fallbackTimer?.invalidate()
    fallbackTimer = nil
    audioTap?.stop()
    audioTap = nil
    metalView.isPaused = true
  }

  private func startAudioTap() -> Bool {
    guard audioTap == nil else { return true }
    let tap = LilithAudioTap(processID: getpid(), analyzer: analyzer) { [weak self] frame in
      DispatchQueue.main.async {
        self?.renderer?.update(with: frame)
      }
    }
    audioTap = tap
    let didStart = tap.start()
    if !didStart {
      audioTap = nil
    }
    return didStart
  }

  private func startFallbackMotion() {
    fallbackTimer?.invalidate()
    fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      guard let self else { return }
      let time = CACurrentMediaTime()
      let samples = (0..<1024).map { index -> Float in
        let x = Float(index) / 44_100
        let t = Float(time)
        return sin((x * 110 + t * 0.17) * .pi * 2) * 0.30
          + sin((x * 440 + t * 0.07) * .pi * 2) * 0.12
      }
      renderer?.update(with: analyzer.analyze(samples: samples, sampleRate: 44_100, time: time))
    }
  }
}
