import Cocoa
import MetalKit
import QuartzCore

final class LilithJamView: NSView {
  private enum PetDance: CaseIterable {
    case bounce
    case sway
    case hop
    case shimmy
    case pop
  }

  private let model = LilithVisualizerModel(
    reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  )
  private let analyzer = LilithAudioAnalyzer()
  private let metalView = MTKView()
  private let controlsView = NSView()
  private let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
  private let rewindButton = NSButton()
  private let playPauseButton = NSButton()
  private let stopButton = NSButton()
  private let forwardButton = NSButton()
  private let nextPresetButton = NSButton()
  private let petImageView = NSImageView()
  private var renderer: LilithMetalRenderer?
  private var audioTap: LilithAudioTap?
  private var fallbackTimer: Timer?
  private var controlsSyncTimer: Timer?
  private var petAnimationTimer: Timer?
  private var petFrames: [NSImage] = []
  private var petSequence: [Int] = []
  private var petFrameIndex = 0
  private var lastPetBeatTime: TimeInterval = 0
  private weak var player: PlayerCore?

  override var acceptsFirstResponder: Bool { true }

  init(player: PlayerCore) {
    self.player = player
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
    layer?.borderWidth = 2
    translatesAutoresizingMaskIntoConstraints = false
    installMetalView()
    installPetView()
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
    case "j", "n":
      advancePreset()
    case " ":
      player?.togglePause()
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

  private func installPetView() {
    petImageView.translatesAutoresizingMaskIntoConstraints = false
    petImageView.imageScaling = .scaleProportionallyUpOrDown
    petImageView.wantsLayer = true
    petImageView.layer?.zPosition = 4
    petImageView.layer?.shadowColor = NSColor.black.cgColor
    petImageView.layer?.shadowOpacity = 0.45
    petImageView.layer?.shadowRadius = 10
    petImageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
    addSubview(petImageView)
    NSLayoutConstraint.activate([
      petImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
      petImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      petImageView.widthAnchor.constraint(equalToConstant: 82),
      petImageView.heightAnchor.constraint(equalToConstant: 98),
    ])
  }

  private func installPresetControls() {
    controlsView.translatesAutoresizingMaskIntoConstraints = false
    controlsView.wantsLayer = true
    controlsView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.95).cgColor
    controlsView.layer?.borderColor = NSColor.white.withAlphaComponent(0.26).cgColor
    controlsView.layer?.borderWidth = 1
    controlsView.layer?.cornerRadius = 8
    controlsView.layer?.masksToBounds = true
    controlsView.layer?.zPosition = 10

    let titleLabel = NSTextField(labelWithString: "Visuals")
    titleLabel.textColor = NSColor.white.withAlphaComponent(0.9)
    titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

    configureControlButton(rewindButton, symbol: "gobackward.10", fallbackTitle: "-10", action: #selector(seekBackward), label: "Back 10 seconds")
    configureControlButton(playPauseButton, symbol: "pause.fill", fallbackTitle: "Pause", action: #selector(togglePlayPause), label: "Play or pause")
    configureControlButton(stopButton, symbol: "stop.fill", fallbackTitle: "Stop", action: #selector(stopPlayback), label: "Stop")
    configureControlButton(forwardButton, symbol: "goforward.10", fallbackTitle: "+10", action: #selector(seekForward), label: "Forward 10 seconds")

    presetPopup.addItems(withTitles: model.presets.map(\.name))
    presetPopup.target = self
    presetPopup.action = #selector(selectPresetFromPopup(_:))
    presetPopup.controlSize = .regular
    presetPopup.setAccessibilityLabel("Visuals")

    configureControlButton(nextPresetButton, symbol: "sparkles", fallbackTitle: "Next", action: #selector(selectNextPreset), label: "Next visual")

    let stack = NSStackView(views: [
      rewindButton,
      playPauseButton,
      stopButton,
      forwardButton,
      titleLabel,
      presetPopup,
      nextPresetButton,
    ])
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
      presetPopup.widthAnchor.constraint(equalToConstant: 150),
      rewindButton.widthAnchor.constraint(equalToConstant: 34),
      playPauseButton.widthAnchor.constraint(equalToConstant: 38),
      stopButton.widthAnchor.constraint(equalToConstant: 34),
      forwardButton.widthAnchor.constraint(equalToConstant: 34),
      nextPresetButton.widthAnchor.constraint(equalToConstant: 34),
    ])
    [rewindButton, playPauseButton, stopButton, forwardButton, nextPresetButton].forEach {
      $0.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
  }

  private func configureControlButton(
    _ button: NSButton,
    symbol: String,
    fallbackTitle: String,
    action: Selector,
    label: String
  ) {
    button.target = self
    button.action = action
    button.bezelStyle = .texturedRounded
    button.controlSize = .regular
    button.imagePosition = .imageOnly
    button.contentTintColor = NSColor.white.withAlphaComponent(0.92)
    button.setAccessibilityLabel(label)
    setButtonImage(button, symbol: symbol, fallbackTitle: fallbackTitle, label: label)
  }

  private func setButtonImage(_ button: NSButton, symbol: String, fallbackTitle: String, label: String) {
    if #available(macOS 11.0, *) {
      button.title = ""
      let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
      image?.isTemplate = true
      button.image = image
    } else {
      button.title = fallbackTitle
    }
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

  @objc private func togglePlayPause() {
    player?.togglePause()
    syncPlaybackControls()
  }

  @objc private func stopPlayback() {
    player?.stop()
    syncPlaybackControls()
  }

  @objc private func seekBackward() {
    player?.seek(relativeSecond: -10, option: .relative)
  }

  @objc private func seekForward() {
    player?.seek(relativeSecond: 10, option: .relative)
  }

  private func syncPresetControls() {
    presetPopup.selectItem(at: model.presetIndex)
  }

  private func syncPlaybackControls() {
    guard let player else { return }
    let active = player.info.state.active
    [rewindButton, playPauseButton, stopButton, forwardButton].forEach { $0.isEnabled = active }
    let paused = player.info.state == .paused
    setButtonImage(
      playPauseButton,
      symbol: paused ? "play.fill" : "pause.fill",
      fallbackTitle: paused ? "Play" : "Pause",
      label: paused ? "Play" : "Pause"
    )
  }

  private func start() {
    model.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    loadPetFramesIfNeeded()
    syncPlaybackControls()
    startControlSync()
    if !startAudioTap() {
      startFallbackMotion()
    }
    metalView.isPaused = false
  }

  private func stop() {
    fallbackTimer?.invalidate()
    fallbackTimer = nil
    controlsSyncTimer?.invalidate()
    controlsSyncTimer = nil
    petAnimationTimer?.invalidate()
    petAnimationTimer = nil
    audioTap?.stop()
    audioTap = nil
    metalView.isPaused = true
  }

  private func startControlSync() {
    controlsSyncTimer?.invalidate()
    controlsSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
      self?.syncPlaybackControls()
    }
  }

  private func startAudioTap() -> Bool {
    guard audioTap == nil else { return true }
    let tap = LilithAudioTap(processID: getpid(), analyzer: analyzer) { [weak self] frame in
      DispatchQueue.main.async {
        self?.handleAudioFrame(frame)
      }
    }
    audioTap = tap
    let didStart = tap.start()
    if !didStart {
      audioTap = nil
    }
    return didStart
  }

  private func handleAudioFrame(_ frame: AudioFeatureFrame) {
    renderer?.update(with: frame)
    handlePetBeat(frame)
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
      handleAudioFrame(analyzer.analyze(samples: samples, sampleRate: 44_100, time: time))
    }
  }

  private func loadPetFramesIfNeeded() {
    guard petFrames.isEmpty else { return }
    guard let image = NSImage(named: "LilithPetSprite"),
          let sheet = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      petImageView.isHidden = true
      return
    }
    let columns = 8
    let rows = 9
    let frameWidth = sheet.width / columns
    let frameHeight = sheet.height / rows
    petFrames = (0..<(columns * rows)).compactMap { index in
      let col = index % columns
      let row = index / columns
      let rect = CGRect(x: col * frameWidth, y: row * frameHeight, width: frameWidth, height: frameHeight)
      guard let crop = sheet.cropping(to: rect) else { return nil }
      return NSImage(cgImage: crop, size: NSSize(width: frameWidth, height: frameHeight))
    }
    petImageView.image = petFrames.first
    petImageView.isHidden = petFrames.isEmpty
  }

  private func handlePetBeat(_ frame: AudioFeatureFrame) {
    guard frame.isBeat, !petFrames.isEmpty else { return }
    let now = frame.time > 0 ? frame.time : CACurrentMediaTime()
    guard now - lastPetBeatTime > 0.22 else { return }
    lastPetBeatTime = now
    startPetDance(PetDance.allCases.randomElement() ?? .bounce, intensity: max(frame.bass, frame.rms))
  }

  private func startPetDance(_ dance: PetDance, intensity: Float) {
    let sequences: [PetDance: [Int]] = [
      .bounce: [0, 1, 2, 3, 4, 5, 4, 3],
      .sway: [8, 9, 10, 11, 12, 13, 14, 15],
      .hop: [16, 17, 18, 19, 20, 21, 22, 23],
      .shimmy: [24, 25, 26, 27, 26, 25],
      .pop: [32, 33, 34, 35, 36, 35, 34, 33],
    ]
    petSequence = sequences[dance] ?? [0]
    petFrameIndex = 0
    advancePetFrame()
    petAnimationTimer?.invalidate()
    petAnimationTimer = Timer.scheduledTimer(
      withTimeInterval: max(0.045, 0.11 - Double(intensity) * 0.04),
      repeats: true
    ) { [weak self] _ in
      self?.advancePetFrame()
    }
    animatePetMotion(dance, intensity: intensity)
  }

  private func advancePetFrame() {
    guard !petFrames.isEmpty, !petSequence.isEmpty else { return }
    let frame = petSequence[petFrameIndex % petSequence.count]
    if petFrames.indices.contains(frame) {
      petImageView.image = petFrames[frame]
    }
    petFrameIndex += 1
  }

  private func animatePetMotion(_ dance: PetDance, intensity: Float) {
    guard let layer = petImageView.layer else { return }
    let strength = CGFloat(0.7 + intensity)
    let duration = CFTimeInterval(max(0.24, 0.46 - Double(intensity) * 0.12))

    func add(_ keyPath: String, _ values: [CGFloat], _ key: String) {
      let animation = CAKeyframeAnimation(keyPath: keyPath)
      animation.values = values.map { NSNumber(value: Double($0)) }
      animation.duration = duration
      animation.isAdditive = true
      animation.calculationMode = .cubic
      layer.add(animation, forKey: key)
    }

    switch dance {
    case .bounce:
      add("transform.translation.y", [0, -4 * strength, 16 * strength, 0], "lilithBounce")
    case .sway:
      add("transform.rotation.z", [-0.16 * strength, 0.18 * strength, -0.10 * strength, 0], "lilithSway")
    case .hop:
      add("transform.translation.y", [0, 22 * strength, 4 * strength, 0], "lilithHopY")
      add("transform.scale", [1, 1.08 + CGFloat(intensity) * 0.08, 0.96, 1], "lilithHopScale")
    case .shimmy:
      add("transform.translation.x", [-9 * strength, 9 * strength, -6 * strength, 6 * strength, 0], "lilithShimmy")
    case .pop:
      add("transform.rotation.z", [0, 0.28 * strength, -0.24 * strength, 0.10 * strength, 0], "lilithPopSpin")
      add("transform.scale", [1, 1.12 + CGFloat(intensity) * 0.08, 0.98, 1], "lilithPopScale")
    }
  }
}
