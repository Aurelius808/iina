import Cocoa
import MetalKit
import QuartzCore

final class LilithJamView: NSView {
  private let model = LilithVisualizerModel(
    reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  )
  private let analyzer = LilithAudioAnalyzer()
  private let metalView = MTKView()
  private let controlsView = NSView()
  private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let nextPresetButton = NSButton()
  private var renderer: LilithMetalRenderer?
  private var audioTap: LilithAudioTap?
  private var fallbackTimer: Timer?
  private weak var player: PlayerCore?

  override var acceptsFirstResponder: Bool { true }

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    translatesAutoresizingMaskIntoConstraints = false
    installMetalView()
    installPresetControls()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setActive(_ active: Bool) {
    isHidden = !active
    if active {
      start()
      window?.makeFirstResponder(self)
    } else {
      stop()
    }
  }

  func advancePreset() {
    renderer?.advancePreset()
    syncPresetControls()
  }

  func selectPreset(at index: Int) {
    guard model.presets.indices.contains(index) else { return }
    model.selectPreset(id: model.presets[index].id)
    syncPresetControls()
  }

  var presetIndex: Int {
    model.presetIndex
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard !isHidden else { return nil }
    let controlsPoint = controlsView.convert(point, from: self)
    return controlsView.hitTest(controlsPoint)
  }

  override func mouseUp(with event: NSEvent) {
    advancePreset()
  }

  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "j", "n", " ":
      advancePreset()
    default:
      if event.keyCode == 124 {
        advancePreset()
      } else {
        super.keyDown(with: event)
      }
    }
  }

  private func installMetalView() {
    metalView.translatesAutoresizingMaskIntoConstraints = false
    metalView.wantsLayer = true
    metalView.layer?.zPosition = 0
    addSubview(metalView)
    NSLayoutConstraint.activate([
      metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
      metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
      metalView.topAnchor.constraint(equalTo: topAnchor),
      metalView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    renderer = LilithMetalRenderer(mtkView: metalView, model: model)
  }

  private func installPresetControls() {
    controlsView.translatesAutoresizingMaskIntoConstraints = false
    controlsView.wantsLayer = true
    controlsView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
    controlsView.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
    controlsView.layer?.borderWidth = 1
    controlsView.layer?.cornerRadius = 8
    controlsView.layer?.masksToBounds = true
    controlsView.layer?.zPosition = 10

    let titleLabel = NSTextField(labelWithString: "Visuals")
    titleLabel.textColor = NSColor.white.withAlphaComponent(0.9)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    presetPopup.addItems(withTitles: model.presets.map(\.name))
    presetPopup.target = self
    presetPopup.action = #selector(selectPresetFromPopup(_:))
    presetPopup.controlSize = .regular
    presetPopup.setAccessibilityLabel("Visuals")

    nextPresetButton.target = self
    nextPresetButton.action = #selector(selectNextPreset)
    nextPresetButton.bezelStyle = .texturedRounded
    nextPresetButton.controlSize = .regular
    nextPresetButton.setAccessibilityLabel("Next visual")
    if #available(macOS 11.0, *) {
      nextPresetButton.title = ""
      nextPresetButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next visual")
    } else {
      nextPresetButton.title = "Next"
    }

    let stack = NSStackView(views: [titleLabel, presetPopup, nextPresetButton])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8

    controlsView.addSubview(stack)
    addSubview(controlsView)
    NSLayoutConstraint.activate([
      controlsView.centerXAnchor.constraint(equalTo: centerXAnchor),
      controlsView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -10),
      presetPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
      nextPresetButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
      nextPresetButton.heightAnchor.constraint(equalToConstant: 28),
    ])
  }

  @objc private func selectPresetFromPopup(_ sender: NSPopUpButton) {
    let index = sender.indexOfSelectedItem
    guard model.presets.indices.contains(index) else { return }
    model.selectPreset(id: model.presets[index].id)
    syncPresetControls()
  }

  @objc private func selectNextPreset() {
    advancePreset()
  }

  private func syncPresetControls() {
    presetPopup.selectItem(at: model.presetIndex)
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
