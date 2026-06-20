import Foundation
import Metal
import MetalKit
import QuartzCore

public final class LilithMetalRenderer: NSObject, MTKViewDelegate {
  private struct Uniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var rms: Float
    var bass: Float
    var mid: Float
    var treble: Float
    var beat: Float
    var presetIndex: Float
    var visualStyle: Float
    var reducedMotion: Float
    var intensity: Float
    var accentA: SIMD4<Float>
    var accentB: SIMD4<Float>
    var bandA: SIMD4<Float>
    var bandB: SIMD4<Float>
  }

  private let device: MTLDevice
  private let commandQueue: MTLCommandQueue
  private let pipeline: MTLRenderPipelineState
  private let model: LilithVisualizerModel
  private var startTime = CACurrentMediaTime()

  public init?(mtkView: MTKView, model: LilithVisualizerModel) {
    guard
      let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
      let commandQueue = device.makeCommandQueue()
    else { return nil }

    self.device = device
    self.commandQueue = commandQueue
    self.model = model
    mtkView.device = device
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = true
    mtkView.enableSetNeedsDisplay = false
    mtkView.isPaused = false
    mtkView.preferredFramesPerSecond = 60

    do {
      let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "lilithVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "lilithFragment")
      descriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
      self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
      return nil
    }

    super.init()
    mtkView.delegate = self
  }

  public func update(with frame: AudioFeatureFrame) {
    _ = model.update(with: frame)
  }

  public func advancePreset() {
    model.advancePreset()
  }

  public func draw(in view: MTKView) {
    guard
      let descriptor = view.currentRenderPassDescriptor,
      let drawable = view.currentDrawable,
      let commandBuffer = commandQueue.makeCommandBuffer(),
      let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    else { return }

    let state = model.state
    let bands = spectrumBands(from: state.frame.bands)
    var uniforms = Uniforms(
      resolution: SIMD2<Float>(Float(max(view.drawableSize.width, 1)), Float(max(view.drawableSize.height, 1))),
      time: Float(CACurrentMediaTime() - startTime),
      rms: state.frame.rms,
      bass: state.frame.bass,
      mid: state.frame.mid,
      treble: state.frame.treble,
      beat: state.frame.isBeat ? 1 : 0,
      presetIndex: Float(model.presetIndex),
      visualStyle: Float(state.preset.visualStyle),
      reducedMotion: state.reducedMotion ? 1 : 0,
      intensity: state.intensity,
      accentA: state.preset.accentA,
      accentB: state.preset.accentB,
      bandA: bands.0,
      bandB: bands.1
    )

    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  private func spectrumBands(from bands: [Float]) -> (SIMD4<Float>, SIMD4<Float>) {
    guard !bands.isEmpty else {
      return (.zero, .zero)
    }
    let compact = (0..<8).map { index -> Float in
      let start = index * bands.count / 8
      let end = max(start + 1, (index + 1) * bands.count / 8)
      let safeEnd = min(end, bands.count)
      let slice = bands[start..<safeEnd]
      return slice.reduce(0, +) / Float(slice.count)
    }
    return (
      SIMD4<Float>(compact[0], compact[1], compact[2], compact[3]),
      SIMD4<Float>(compact[4], compact[5], compact[6], compact[7])
    )
  }

  private static let shaderSource = """
  #include <metal_stdlib>
  using namespace metal;

  struct Uniforms {
    float2 resolution;
    float time;
    float rms;
    float bass;
    float mid;
    float treble;
    float beat;
    float presetIndex;
    float visualStyle;
    float reducedMotion;
    float intensity;
    float4 accentA;
    float4 accentB;
    float4 bandA;
    float4 bandB;
  };

  struct VertexOut {
    float4 position [[position]];
    float2 uv;
  };

  vertex VertexOut lilithVertex(uint vertexID [[vertex_id]]) {
    float2 positions[3] = {
      float2(-1.0, -1.0),
      float2( 3.0, -1.0),
      float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = positions[vertexID] * 0.5 + 0.5;
    return out;
  }

  float lilithBand(constant Uniforms& u, int index) {
    if (index == 0) return u.bandA.x;
    if (index == 1) return u.bandA.y;
    if (index == 2) return u.bandA.z;
    if (index == 3) return u.bandA.w;
    if (index == 4) return u.bandB.x;
    if (index == 5) return u.bandB.y;
    if (index == 6) return u.bandB.z;
    return u.bandB.w;
  }

  float lilithHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
  }

  float3 lilithPalette(constant Uniforms& u, float v) {
    return mix(u.accentA.rgb, u.accentB.rgb, clamp(v, 0.0, 1.0));
  }

  fragment float4 lilithFragment(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 uv = in.uv;
    float2 p = (in.uv * u.resolution - 0.5 * u.resolution) / max(u.resolution.y, 1.0);
    float reduced = mix(1.0, 0.28, u.reducedMotion);
    float pulse = 0.08 + u.intensity * 0.5 + u.beat * 0.16;
    float t = u.time * (0.16 + u.bass * 0.28) * reduced;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float style = floor(u.visualStyle + 0.5);
    float3 color = float3(0.0);

    if (style < 0.5) {
      float petals = sin(a * 5.0 + t * 7.0 + sin(r * 18.0 - t * 2.0 + u.bandA.y * 6.0));
      float rings = sin((r - pulse) * (22.0 + u.mid * 18.0) - t * 5.0);
      float star = pow(max(0.0, 1.0 - abs(petals * rings)), 3.0);
      float core = smoothstep(0.42 + pulse, 0.02, r);
      float sparks = smoothstep(0.92, 1.0, sin(a * 23.0 + t * 11.0) * cos(r * 37.0 - t * 3.0));
      color = lilithPalette(u, star + u.treble * 0.7);
      color *= 0.10 + core * 0.95 + star * 0.75 + sparks * u.intensity * 0.38;
    } else if (style < 1.5) {
      float tunnel = sin((1.0 / max(r + 0.18 + u.bass * 0.2, 0.04)) * 2.8 + a * 7.0 + t * 4.0);
      float glow = pow(max(0.0, tunnel), 3.0) + smoothstep(0.22 + u.bass * 0.25, 0.02, abs(r - 0.38 - u.mid * 0.18));
      color = lilithPalette(u, 0.35 + tunnel * 0.5 + u.treble * 0.4) * glow;
    } else if (style < 2.5) {
      float water = sin((p.x + sin(p.y * 3.0 + t * 2.0)) * (9.0 + u.bandA.z * 10.0));
      water += cos((p.y + cos(p.x * 4.0 - t)) * (8.0 + u.treble * 9.0));
      float shimmer = smoothstep(0.25, 1.0, abs(water) * (0.5 + u.mid));
      color = lilithPalette(u, 0.45 + 0.45 * sin(water + t)) * shimmer * (0.35 + u.intensity);
    } else if (style < 3.5) {
      float rings = sin(r * (34.0 + u.bass * 22.0) - t * 8.0 + u.bandA.x * 8.0);
      float spokes = sin(a * (9.0 + u.bandA.y * 10.0) + t * (3.0 + u.mid * 5.0));
      float warp = pow(max(0.0, 1.0 - abs(rings * spokes)), 2.5);
      color = lilithPalette(u, warp + u.treble * 0.5) * (warp + smoothstep(0.48, 0.0, r) * (0.4 + u.bass));
    } else if (style < 4.5) {
      int band = int(floor(clamp(uv.x, 0.0, 0.999) * 8.0));
      float level = lilithBand(u, band);
      float centerLevel = 0.08 + level * (0.82 + u.intensity * 0.3);
      float bar = smoothstep(centerLevel + 0.02, centerLevel - 0.02, abs(uv.y - 0.5) * 2.0);
      float lane = smoothstep(0.48, 0.36, abs(fract(uv.x * 8.0) - 0.5));
      float scan = 0.72 + 0.28 * sin(uv.y * 70.0 - t * 16.0);
      color = lilithPalette(u, float(band) / 7.0) * bar * lane * scan * (0.8 + level);
    } else if (style < 5.5) {
      float xBand = lilithBand(u, int(floor(clamp(uv.x, 0.0, 0.999) * 8.0)));
      float wave1 = abs(p.y - sin(p.x * (5.0 + u.mid * 9.0) + t * 4.0) * (0.18 + xBand * 0.26));
      float wave2 = abs(p.y - cos(p.x * (8.0 + u.treble * 12.0) - t * 3.0) * (0.12 + u.bass * 0.22));
      float ribbon = smoothstep(0.05, 0.0, min(wave1, wave2));
      color = lilithPalette(u, 0.3 + xBand + sin(p.x + t) * 0.2) * ribbon * (1.0 + u.intensity);
    } else if (style < 6.5) {
      float reactor = smoothstep(0.22 + u.bass * 0.55, 0.18 + u.bass * 0.32, abs(r - (0.24 + u.bass * 0.28)));
      float shock = smoothstep(0.03, 0.0, abs(sin(r * (42.0 + u.bass * 40.0) - t * 8.0)));
      color = lilithPalette(u, u.bass + shock * 0.3) * (reactor * 1.4 + shock * u.intensity * 0.55);
    } else if (style < 7.5) {
      float2 cell = floor((uv + float2(t * 0.015, -t * 0.01)) * 18.0);
      float2 local = fract((uv + float2(t * 0.015, -t * 0.01)) * 18.0) - 0.5;
      float h = lilithHash(cell);
      int band = int(floor(h * 8.0));
      float twinkle = smoothstep(0.06 + lilithBand(u, band) * 0.08, 0.0, length(local));
      color = lilithPalette(u, h + u.treble * 0.4) * twinkle * (0.6 + u.treble * 2.0);
    } else if (style < 8.5) {
      float orbit = abs(sin(a * 3.0 + t * (2.0 + u.bass * 4.0)) * 0.28 + 0.34 + u.bandA.x * 0.16 - r);
      float moons = smoothstep(0.03 + u.mid * 0.02, 0.0, orbit);
      float halo = smoothstep(0.8, 0.08, r) * (0.08 + u.bass * 0.6);
      color = lilithPalette(u, r + u.mid) * (moons * 1.2 + halo);
    } else {
      int band = int(floor(clamp((p.x + 0.5) * 8.0, 0.0, 7.0)));
      float level = lilithBand(u, band);
      float stem = smoothstep(0.015, 0.0, abs(p.x - (float(band) / 7.0 - 0.5)));
      float bloom = smoothstep(0.16 + level * 0.3, 0.0, distance(p, float2(float(band) / 7.0 - 0.5, -0.28 + level * 0.65)));
      color = lilithPalette(u, float(band) / 7.0 + level * 0.35) * (stem * (0.3 + level) + bloom);
    }

    color += u.beat * min(0.18, u.intensity * 0.22);
    return float4(color, 1.0);
  }
  """
}
