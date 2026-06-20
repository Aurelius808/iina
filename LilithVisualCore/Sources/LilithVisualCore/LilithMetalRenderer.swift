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
    var reducedMotion: Float
    var intensity: Float
    var accentA: SIMD4<Float>
    var accentB: SIMD4<Float>
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
    var uniforms = Uniforms(
      resolution: SIMD2<Float>(Float(max(view.drawableSize.width, 1)), Float(max(view.drawableSize.height, 1))),
      time: Float(CACurrentMediaTime() - startTime),
      rms: state.frame.rms,
      bass: state.frame.bass,
      mid: state.frame.mid,
      treble: state.frame.treble,
      beat: state.frame.isBeat ? 1 : 0,
      presetIndex: Float(model.presetIndex),
      reducedMotion: state.reducedMotion ? 1 : 0,
      intensity: state.intensity,
      accentA: state.preset.accentA,
      accentB: state.preset.accentB
    )

    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

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
    float reducedMotion;
    float intensity;
    float4 accentA;
    float4 accentB;
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

  fragment float4 lilithFragment(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 p = (in.uv * u.resolution - 0.5 * u.resolution) / max(u.resolution.y, 1.0);
    float reduced = mix(1.0, 0.28, u.reducedMotion);
    float pulse = 0.08 + u.intensity * 0.5 + u.beat * 0.16;
    float t = u.time * (0.16 + u.bass * 0.28) * reduced;
    float r = length(p);
    float a = atan2(p.y, p.x);
    float petals = sin(a * (5.0 + fmod(u.presetIndex, 3.0)) + t * 7.0 + sin(r * 18.0 - t * 2.0));
    float rings = sin((r - pulse) * (22.0 + u.mid * 18.0) - t * 5.0);
    float star = pow(max(0.0, 1.0 - abs(petals * rings)), 3.0);
    float core = smoothstep(0.42 + pulse, 0.02, r);
    float sparks = smoothstep(0.92, 1.0, sin(a * 23.0 + t * 11.0) * cos(r * 37.0 - t * 3.0));
    float3 color = mix(u.accentA.rgb, u.accentB.rgb, clamp(star + u.treble * 0.7, 0.0, 1.0));
    color *= 0.10 + core * 0.95 + star * 0.75 + sparks * u.intensity * 0.38;
    color += u.beat * min(0.18, u.intensity * 0.22);
    return float4(color, 1.0);
  }
  """
}
