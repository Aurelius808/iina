import Foundation

public struct AudioFeatureFrame: Equatable, Sendable {
  public var time: TimeInterval
  public var rms: Float
  public var bass: Float
  public var mid: Float
  public var treble: Float
  public var isBeat: Bool
  public var bands: [Float]

  public init(
    time: TimeInterval = 0,
    rms: Float = 0,
    bass: Float = 0,
    mid: Float = 0,
    treble: Float = 0,
    isBeat: Bool = false,
    bands: [Float] = []
  ) {
    self.time = time
    self.rms = rms
    self.bass = bass
    self.mid = mid
    self.treble = treble
    self.isBeat = isBeat
    self.bands = bands
  }

  public static let silent = AudioFeatureFrame()
}
