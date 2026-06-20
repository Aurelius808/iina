import Foundation

public struct LilithPreset: Equatable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let accentA: SIMD4<Float>
  public let accentB: SIMD4<Float>
  public let motionGain: Float
  public let flashCap: Float

  public init(
    id: String,
    name: String,
    accentA: SIMD4<Float>,
    accentB: SIMD4<Float>,
    motionGain: Float,
    flashCap: Float
  ) {
    self.id = id
    self.name = name
    self.accentA = accentA
    self.accentB = accentB
    self.motionGain = motionGain
    self.flashCap = flashCap
  }

  public static let builtIns: [LilithPreset] = [
    LilithPreset(
      id: "black-rose",
      name: "Black Rose",
      accentA: SIMD4<Float>(0.85, 0.05, 0.24, 1.0),
      accentB: SIMD4<Float>(0.05, 0.85, 0.92, 1.0),
      motionGain: 1.0,
      flashCap: 0.42
    ),
    LilithPreset(
      id: "neon-altar",
      name: "Neon Altar",
      accentA: SIMD4<Float>(0.98, 0.46, 0.09, 1.0),
      accentB: SIMD4<Float>(0.12, 0.35, 0.94, 1.0),
      motionGain: 0.82,
      flashCap: 0.36
    ),
    LilithPreset(
      id: "glass-tide",
      name: "Glass Tide",
      accentA: SIMD4<Float>(0.16, 0.76, 0.58, 1.0),
      accentB: SIMD4<Float>(0.91, 0.16, 0.74, 1.0),
      motionGain: 0.72,
      flashCap: 0.30
    ),
  ]
}
