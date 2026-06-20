import Cocoa
import MetalKit
import QuartzCore

private final class LilithControlButton: NSButton {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

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
  private let previousTrackButton = LilithControlButton()
  private let rewindButton = LilithControlButton()
  private let playPauseButton = LilithControlButton()
  private let stopButton = LilithControlButton()
  private let forwardButton = LilithControlButton()
  private let nextTrackButton = LilithControlButton()
  private let repeatButton = LilithControlButton()
  private let shuffleButton = LilithControlButton()
  private let playlistButton = LilithControlButton()
  private let nextPresetButton = LilithControlButton()
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
  private var lastPetEnergy: Float = 0
  private var petPosition = CGPoint(x: 0.20, y: 0.18)
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
    let target = super.hitTest(point)
    if target === self || target === metalView || target === petImageView {
      return nil
    }
    return target
  }

  override func mouseUp(with event: NSEvent) {
    advancePreset()
  }

  override func layout() {
    super.layout()
    updatePetLayout(animated: false)
  }

  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "j", "n":
      advancePreset()
    case " ":
      togglePlayPause()
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
    petImageView.translatesAutoresizingMaskIntoConstraints = true
    petImageView.imageScaling = .scaleProportionallyUpOrDown
    petImageView.wantsLayer = true
    petImageView.layer?.zPosition = 4
    petImageView.layer?.shadowColor = NSColor.black.cgColor
    petImageView.layer?.shadowOpacity = 0.45
    petImageView.layer?.shadowRadius = 10
    petImageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
    addSubview(petImageView)
    updatePetLayout(animated: false)
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

    configureControlButton(previousTrackButton, symbol: "backward.end.fill", fallbackTitle: "Prev", action: #selector(previousTrack), label: "Previous track")
    configureControlButton(rewindButton, symbol: "gobackward.10", fallbackTitle: "-10", action: #selector(seekBackward), label: "Back 10 seconds")
    configureControlButton(playPauseButton, symbol: "pause.fill", fallbackTitle: "Pause", action: #selector(togglePlayPause), label: "Play or pause")
    configureControlButton(stopButton, symbol: "stop.fill", fallbackTitle: "Stop", action: #selector(stopPlayback), label: "Stop")
    configureControlButton(forwardButton, symbol: "goforward.10", fallbackTitle: "+10", action: #selector(seekForward), label: "Forward 10 seconds")
    configureControlButton(nextTrackButton, symbol: "forward.end.fill", fallbackTitle: "Next", action: #selector(nextTrack), label: "Next track")
    configureControlButton(repeatButton, symbol: "repeat.1", fallbackTitle: "Repeat", action: #selector(toggleAutoReplay), label: "Auto replay")
    configureControlButton(shuffleButton, symbol: "shuffle", fallbackTitle: "Random", action: #selector(shufflePlaylist), label: "Random playlist")
    configureControlButton(playlistButton, symbol: "list.bullet", fallbackTitle: "List", action: #selector(togglePlaylistPanel), label: "Playlist")

    presetPopup.addItems(withTitles: model.presets.map(\.name))
    presetPopup.target = self
    presetPopup.action = #selector(selectPresetFromPopup(_:))
    presetPopup.controlSize = .regular
    presetPopup.setAccessibilityLabel("Visuals")

    configureControlButton(nextPresetButton, symbol: "sparkles", fallbackTitle: "Next", action: #selector(selectNextPreset), label: "Next visual")

    let stack = NSStackView(views: [
      previousTrackButton,
      rewindButton,
      playPauseButton,
      stopButton,
      forwardButton,
      nextTrackButton,
      repeatButton,
      shuffleButton,
      playlistButton,
      presetPopup,
      nextPresetButton,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 5

    controlsView.addSubview(stack)
    addSubview(controlsView)
    NSLayoutConstraint.activate([
      controlsView.centerXAnchor.constraint(equalTo: centerXAnchor),
      controlsView.centerYAnchor.constraint(equalTo: centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: controlsView.bottomAnchor, constant: -10),
      presetPopup.widthAnchor.constraint(equalToConstant: 132),
    ])
    transportButtons.forEach {
      $0.widthAnchor.constraint(equalToConstant: 28).isActive = true
      $0.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
  }

  private var transportButtons: [LilithControlButton] {
    [
      previousTrackButton,
      rewindButton,
      playPauseButton,
      stopButton,
      forwardButton,
      nextTrackButton,
      repeatButton,
      shuffleButton,
      playlistButton,
      nextPresetButton,
    ]
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
    button.setAccessibilityLabel(label)
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

  @objc private func previousTrack() {
    player?.navigateInPlaylist(nextMedia: false)
    syncPlaybackControls()
  }

  @objc private func nextTrack() {
    player?.navigateInPlaylist(nextMedia: true)
    syncPlaybackControls()
  }

  @objc private func togglePlayPause() {
    guard let player, player.info.state.active else { return }
    if player.mpv.getFlag(MPVOption.PlaybackControl.pause) {
      player.resume()
    } else {
      player.pause()
    }
    syncPlaybackControls()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
      self?.syncPlaybackControls()
    }
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

  @objc private func toggleAutoReplay() {
    guard let player else { return }
    player.setLoopMode(player.getLoopMode() == .file ? .off : .file)
    syncPlaybackControls()
  }

  @objc private func shufflePlaylist() {
    player?.toggleShuffle()
    syncPlaybackControls()
  }

  @objc private func togglePlaylistPanel() {
    player?.mainWindow.sidebars.showPlaylist(tab: .playlist)
  }

  private func syncPresetControls() {
    presetPopup.selectItem(at: model.presetIndex)
  }

  private func syncPlaybackControls() {
    guard let player else { return }
    let active = player.info.state.active
    [
      previousTrackButton,
      rewindButton,
      playPauseButton,
      stopButton,
      forwardButton,
      nextTrackButton,
      repeatButton,
      shuffleButton,
    ].forEach { $0.isEnabled = active }
    playlistButton.isEnabled = true
    nextPresetButton.isEnabled = true
    let paused = active && player.mpv.getFlag(MPVOption.PlaybackControl.pause)
    setButtonImage(
      playPauseButton,
      symbol: paused ? "play.fill" : "pause.fill",
      fallbackTitle: paused ? "Play" : "Pause",
      label: paused ? "Play" : "Pause"
    )
    repeatButton.contentTintColor = player.getLoopMode() == .file
      ? NSColor.systemGreen
      : NSColor.white.withAlphaComponent(0.92)
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
    let rows = 5
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
    updatePetLayout(animated: false)
  }

  private func handlePetBeat(_ frame: AudioFeatureFrame) {
    guard !petFrames.isEmpty else { return }
    let now = frame.time > 0 ? frame.time : CACurrentMediaTime()
    let energy = max(frame.rms * 0.45 + frame.bass * 0.40 + frame.mid * 0.15, frame.bass)
    let transient = frame.isBeat || (energy > max(0.12, lastPetEnergy * 1.28) && energy - lastPetEnergy > 0.06)
    lastPetEnergy = lastPetEnergy * 0.82 + energy * 0.18
    guard transient, now - lastPetBeatTime > 0.18 else { return }
    lastPetBeatTime = now
    startPetDance(PetDance.allCases.randomElement() ?? .bounce, intensity: max(energy, frame.treble))
  }

  private func startPetDance(_ dance: PetDance, intensity: Float) {
    petPosition = CGPoint(
      x: CGFloat.random(in: 0.16...0.84),
      y: CGFloat.random(in: 0.12...0.38)
    )
    updatePetLayout(animated: true)

    let sequences: [PetDance: [Int]] = [
      .bounce: Array(0..<8),
      .sway: Array(8..<16),
      .hop: Array(16..<24),
      .shimmy: Array(24..<32),
      .pop: Array(32..<40),
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

  private func updatePetLayout(animated: Bool) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    let side = min(max(min(bounds.width, bounds.height) * 0.24, 86), 190)
    let frame = CGRect(
      x: petPosition.x * max(bounds.width - side, 0),
      y: petPosition.y * max(bounds.height - side, 0),
      width: side,
      height: side
    )
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.16
        context.timingFunction = CAMediaTimingFunction(name: .easeOut)
        petImageView.animator().frame = frame
      }
    } else {
      petImageView.frame = frame
    }
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
      add("transform.translation.y", [0, -8 * strength, 24 * strength, -4 * strength, 0], "lilithBounce")
    case .sway:
      add("transform.rotation.z", [-0.22 * strength, 0.24 * strength, -0.16 * strength, 0.12 * strength, 0], "lilithSway")
      add("transform.translation.x", [-12 * strength, 12 * strength, -8 * strength, 0], "lilithSwayX")
    case .hop:
      add("transform.translation.y", [0, 34 * strength, 8 * strength, 0], "lilithHopY")
      add("transform.scale", [1, 1.16 + CGFloat(intensity) * 0.12, 0.92, 1], "lilithHopScale")
    case .shimmy:
      add("transform.translation.x", [-15 * strength, 15 * strength, -12 * strength, 12 * strength, 0], "lilithShimmy")
      add("transform.rotation.z", [0.10 * strength, -0.10 * strength, 0.08 * strength, -0.08 * strength, 0], "lilithShimmySpin")
    case .pop:
      add("transform.rotation.z", [0, 0.45 * strength, -0.36 * strength, 0.18 * strength, 0], "lilithPopSpin")
      add("transform.scale", [1, 1.24 + CGFloat(intensity) * 0.16, 0.90, 1.06, 1], "lilithPopScale")
    }
  }
}
