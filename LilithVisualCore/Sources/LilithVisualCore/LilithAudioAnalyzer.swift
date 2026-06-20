import Accelerate
import Foundation
import QuartzCore

public final class LilithAudioAnalyzer {
  private let bandCount: Int
  private let fftSize: Int
  private var energyHistory: [Float] = []
  private let historyLimit = 48

  public init(fftSize: Int = 1024, bandCount: Int = 32) {
    self.fftSize = max(64, 1 << Int(floor(log2(Double(fftSize)))))
    self.bandCount = max(4, bandCount)
  }

  public func analyze(samples: [Float], sampleRate: Double, time: TimeInterval = CACurrentMediaTime()) -> AudioFeatureFrame {
    guard !samples.isEmpty else { return .silent }

    let input = normalizedInput(samples)
    let rms = rootMeanSquare(input)
    let spectrum = magnitudes(for: input)
    let bands = compactBands(spectrum)
    let bass = averageBand(bands, range: 0..<min(4, bands.count))
    let mid = averageBand(bands, range: min(4, bands.count)..<min(14, bands.count))
    let treble = averageBand(bands, range: min(14, bands.count)..<bands.count)
    let beat = detectBeat(energy: bass * 0.65 + rms * 0.35)

    return AudioFeatureFrame(
      time: time,
      rms: rms,
      bass: bass,
      mid: mid,
      treble: treble,
      isBeat: beat,
      bands: bands
    )
  }

  private func normalizedInput(_ samples: [Float]) -> [Float] {
    var output = Array(samples.prefix(fftSize))
    if output.count < fftSize {
      output += Array(repeating: 0, count: fftSize - output.count)
    }
    var window = [Float](repeating: 0, count: fftSize)
    vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul(output, 1, window, 1, &output, 1, vDSP_Length(fftSize))
    return output
  }

  private func rootMeanSquare(_ samples: [Float]) -> Float {
    var meanSquare: Float = 0
    vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(samples.count))
    return sqrt(meanSquare).lilithClamped(to: 0...1)
  }

  private func magnitudes(for samples: [Float]) -> [Float] {
    let log2n = vDSP_Length(log2(Float(fftSize)))
    guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
      return Array(repeating: 0, count: fftSize / 2)
    }
    defer { vDSP_destroy_fftsetup(setup) }

    var real = [Float](repeating: 0, count: fftSize / 2)
    var imaginary = [Float](repeating: 0, count: fftSize / 2)
    var magnitudes = [Float](repeating: 0, count: fftSize / 2)

    real.withUnsafeMutableBufferPointer { realPtr in
      imaginary.withUnsafeMutableBufferPointer { imaginaryPtr in
        var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imaginaryPtr.baseAddress!)
        samples.withUnsafeBytes { rawBuffer in
          let complex = rawBuffer.bindMemory(to: DSPComplex.self).baseAddress!
          vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
      }
    }

    var scale = Float(1.0 / Float(fftSize))
    vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(magnitudes.count))
    return magnitudes.map { min(1, sqrt($0) * 4) }
  }

  private func compactBands(_ spectrum: [Float]) -> [Float] {
    guard !spectrum.isEmpty else { return Array(repeating: 0, count: bandCount) }
    return (0..<bandCount).map { band in
      let start = band * spectrum.count / bandCount
      let end = max(start + 1, (band + 1) * spectrum.count / bandCount)
      return averageBand(spectrum, range: start..<min(end, spectrum.count))
    }
  }

  private func averageBand(_ values: [Float], range: Range<Int>) -> Float {
    guard !values.isEmpty, !range.isEmpty else { return 0 }
    let safeRange = max(0, range.lowerBound)..<min(values.count, range.upperBound)
    guard !safeRange.isEmpty else { return 0 }
    var mean: Float = 0
    vDSP_meanv(Array(values[safeRange]), 1, &mean, vDSP_Length(safeRange.count))
    return mean.lilithClamped(to: 0...1)
  }

  private func detectBeat(energy: Float) -> Bool {
    energyHistory.append(energy)
    if energyHistory.count > historyLimit {
      energyHistory.removeFirst(energyHistory.count - historyLimit)
    }
    guard energyHistory.count >= 8 else { return false }
    let average = energyHistory.reduce(0, +) / Float(energyHistory.count)
    return energy > max(0.08, average * 1.45)
  }
}

private extension Comparable {
  func lilithClamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
