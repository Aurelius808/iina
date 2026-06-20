import Foundation

public struct LilithPreset: Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let accentA: SIMD4<Float>
  public let accentB: SIMD4<Float>
  public let motionGain: Float
  public let flashCap: Float
  public let visualStyle: Int

  public init(
    id: String,
    name: String,
    accentA: SIMD4<Float>,
    accentB: SIMD4<Float>,
    motionGain: Float,
    flashCap: Float,
    visualStyle: Int = 0
  ) {
    self.id = id
    self.name = name
    self.accentA = accentA
    self.accentB = accentB
    self.motionGain = motionGain
    self.flashCap = flashCap
    self.visualStyle = visualStyle
  }

  public static let builtIns: [LilithPreset] = [
    LilithPreset(
      id: "black-rose",
      name: "Black Rose",
      accentA: SIMD4<Float>(0.85, 0.05, 0.24, 1.0),
      accentB: SIMD4<Float>(0.05, 0.85, 0.92, 1.0),
      motionGain: 1.0,
      flashCap: 0.42,
      visualStyle: 0
    ),
    LilithPreset(
      id: "neon-altar",
      name: "Neon Altar",
      accentA: SIMD4<Float>(0.98, 0.46, 0.09, 1.0),
      accentB: SIMD4<Float>(0.12, 0.35, 0.94, 1.0),
      motionGain: 0.82,
      flashCap: 0.36,
      visualStyle: 1
    ),
    LilithPreset(
      id: "glass-tide",
      name: "Glass Tide",
      accentA: SIMD4<Float>(0.16, 0.76, 0.58, 1.0),
      accentB: SIMD4<Float>(0.91, 0.16, 0.74, 1.0),
      motionGain: 0.72,
      flashCap: 0.30,
      visualStyle: 2
    ),
    LilithPreset(
      id: "milkdrop-tunnel",
      name: "MilkDrop Tunnel",
      accentA: SIMD4<Float>(0.20, 0.38, 1.00, 1.0),
      accentB: SIMD4<Float>(1.00, 0.18, 0.74, 1.0),
      motionGain: 1.05,
      flashCap: 0.40,
      visualStyle: 3
    ),
    LilithPreset(
      id: "avs-spectrum",
      name: "AVS Spectrum",
      accentA: SIMD4<Float>(0.12, 1.00, 0.35, 1.0),
      accentB: SIMD4<Float>(1.00, 0.90, 0.12, 1.0),
      motionGain: 0.95,
      flashCap: 0.34,
      visualStyle: 4
    ),
    LilithPreset(
      id: "sonique-ribbons",
      name: "Sonique Ribbons",
      accentA: SIMD4<Float>(0.92, 0.12, 1.00, 1.0),
      accentB: SIMD4<Float>(0.05, 0.92, 1.00, 1.0),
      motionGain: 1.12,
      flashCap: 0.38,
      visualStyle: 5
    ),
    LilithPreset(
      id: "bass-reactor",
      name: "Bass Reactor",
      accentA: SIMD4<Float>(1.00, 0.08, 0.08, 1.0),
      accentB: SIMD4<Float>(0.18, 0.95, 0.30, 1.0),
      motionGain: 1.20,
      flashCap: 0.44,
      visualStyle: 6
    ),
    LilithPreset(
      id: "treble-constellation",
      name: "Treble Constellation",
      accentA: SIMD4<Float>(0.72, 0.90, 1.00, 1.0),
      accentB: SIMD4<Float>(1.00, 0.45, 0.72, 1.0),
      motionGain: 0.86,
      flashCap: 0.28,
      visualStyle: 7
    ),
    LilithPreset(
      id: "subwave-orbit",
      name: "Subwave Orbit",
      accentA: SIMD4<Float>(0.12, 0.78, 0.94, 1.0),
      accentB: SIMD4<Float>(0.95, 0.32, 0.18, 1.0),
      motionGain: 1.10,
      flashCap: 0.42,
      visualStyle: 8
    ),
    LilithPreset(
      id: "frequency-garden",
      name: "Frequency Garden",
      accentA: SIMD4<Float>(0.30, 1.00, 0.55, 1.0),
      accentB: SIMD4<Float>(0.95, 0.40, 0.95, 1.0),
      motionGain: 0.92,
      flashCap: 0.32,
      visualStyle: 9
    ),
  ]
}
