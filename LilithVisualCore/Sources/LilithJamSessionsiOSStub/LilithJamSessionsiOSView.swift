import LilithVisualCore
import SwiftUI

@available(macOS 12.0, iOS 15.0, *)
public struct LilithJamSessionsiOSView: View {
  private let model = LilithVisualizerModel()
  private let analyzer = LilithAudioAnalyzer()

  public init() {}

  public var body: some View {
    TimelineView(.animation) { timeline in
      let time = timeline.date.timeIntervalSinceReferenceDate
      let frame = analyzer.analyze(
        samples: Self.syntheticSamples(time: time),
        sampleRate: 44_100,
        time: time
      )
      let state = model.update(with: frame)
      Canvas { context, size in
        let rect = CGRect(origin: .zero, size: size)
        let base = Color(
          red: Double(state.preset.accentA.x),
          green: Double(state.preset.accentA.y),
          blue: Double(state.preset.accentA.z)
        )
        let glow = Color(
          red: Double(state.preset.accentB.x),
          green: Double(state.preset.accentB.y),
          blue: Double(state.preset.accentB.z)
        )
        context.fill(Path(rect), with: .linearGradient(
          Gradient(colors: [.black, base.opacity(0.65), glow.opacity(0.55)]),
          startPoint: .zero,
          endPoint: CGPoint(x: size.width, y: size.height)
        ))
        let radius = min(size.width, size.height) * CGFloat(0.18 + state.intensity * 0.28)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(ellipseIn: CGRect(
          x: center.x - radius,
          y: center.y - radius,
          width: radius * 2,
          height: radius * 2
        )), with: .color(glow.opacity(0.72)))
      }
    }
  }

  private static func syntheticSamples(time: TimeInterval) -> [Float] {
    (0..<1024).map { index in
      let x = Float(index) / 44_100
      return sin((x * 220 + Float(time)) * .pi * 2) * 0.35
        + sin((x * 880 + Float(time) * 0.5) * .pi * 2) * 0.14
    }
  }
}
