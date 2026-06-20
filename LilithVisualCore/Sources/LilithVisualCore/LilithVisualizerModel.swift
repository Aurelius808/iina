import Foundation

public struct LilithRenderState: Equatable, Sendable {
  public var preset: LilithPreset
  public var frame: AudioFeatureFrame
  public var reducedMotion: Bool
  public var intensity: Float

  public init(
    preset: LilithPreset = LilithPreset.builtIns[0],
    frame: AudioFeatureFrame = .silent,
    reducedMotion: Bool = false,
    intensity: Float = 0
  ) {
    self.preset = preset
    self.frame = frame
    self.reducedMotion = reducedMotion
    self.intensity = intensity
  }
}

public final class LilithVisualizerModel {
  public private(set) var presets: [LilithPreset]
  public private(set) var presetIndex: Int
  public var reducedMotion: Bool
  public private(set) var state: LilithRenderState

  public init(
    presets: [LilithPreset] = LilithPreset.builtIns,
    reducedMotion: Bool = false
  ) {
    let safePresets = presets.isEmpty ? LilithPreset.builtIns : presets
    self.presets = safePresets
    self.presetIndex = 0
    self.reducedMotion = reducedMotion
    self.state = LilithRenderState(preset: safePresets[0], reducedMotion: reducedMotion)
  }

  public func advancePreset() {
    presetIndex = (presetIndex + 1) % presets.count
    state.preset = presets[presetIndex]
  }

  public func selectPreset(id: String) {
    guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
    presetIndex = index
    state.preset = presets[index]
  }

  public func update(with frame: AudioFeatureFrame) -> LilithRenderState {
    let cappedBeat = frame.isBeat ? state.preset.flashCap : 0
    let motion = reducedMotion ? 0.25 : state.preset.motionGain
    let base = min(1, max(0, frame.rms * 1.7 + cappedBeat))
    state.frame = frame
    state.reducedMotion = reducedMotion
    state.intensity = min(1, base * motion)
    return state
  }
}
