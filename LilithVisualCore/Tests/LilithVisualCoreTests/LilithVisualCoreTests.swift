import XCTest
import MetalKit
@testable import LilithVisualCore

final class LilithVisualCoreTests: XCTestCase {
  func testAnalyzerProducesEnergyBands() {
    let analyzer = LilithAudioAnalyzer()
    let samples = sineWave(frequency: 110, sampleRate: 44_100, count: 1024)
    let frame = analyzer.analyze(samples: samples, sampleRate: 44_100)

    XCTAssertGreaterThan(frame.rms, 0.05)
    XCTAssertEqual(frame.bands.count, 32)
    XCTAssertGreaterThan(frame.bass, frame.treble)
  }

  func testBeatDetectionStaysStableForSilence() {
    let analyzer = LilithAudioAnalyzer()
    let frames = (0..<12).map { _ in
      analyzer.analyze(samples: Array(repeating: 0, count: 1024), sampleRate: 44_100)
    }

    XCTAssertFalse(frames.contains(where: { $0.isBeat }))
  }

  func testPresetSwitchingWraps() {
    let model = LilithVisualizerModel(presets: LilithPreset.builtIns)
    let first = model.state.preset.id
    LilithPreset.builtIns.forEach { _ in model.advancePreset() }

    XCTAssertEqual(model.state.preset.id, first)
    XCTAssertGreaterThanOrEqual(model.presets.count, 10)
    XCTAssertEqual(Set(model.presets.map(\.id)).count, model.presets.count)
  }

  func testMetalRendererCompilesBuiltInVisuals() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw XCTSkip("Metal unavailable")
    }
    let view = MTKView(frame: CGRect(x: 0, y: 0, width: 320, height: 180), device: device)
    let model = LilithVisualizerModel(presets: LilithPreset.builtIns)

    XCTAssertNotNil(LilithMetalRenderer(mtkView: view, model: model))
  }

  func testReducedMotionCapsIntensity() {
    let model = LilithVisualizerModel(reducedMotion: true)
    let state = model.update(with: AudioFeatureFrame(rms: 1, bass: 1, mid: 1, treble: 1, isBeat: true))

    XCTAssertLessThanOrEqual(state.intensity, 0.36)
  }

  private func sineWave(frequency: Float, sampleRate: Float, count: Int) -> [Float] {
    (0..<count).map { index in
      sin((Float(index) / sampleRate) * frequency * .pi * 2)
    }
  }
}
