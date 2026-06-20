import AudioToolbox
import AVFoundation
import Foundation

final class LilithAudioTap {
  private let processID: pid_t
  private let analyzer: LilithAudioAnalyzer
  private let onFrame: (AudioFeatureFrame) -> Void
  private let queue = DispatchQueue(label: "LilithJamSessions.AudioTap", qos: .userInteractive)
  private var processTapID: AudioObjectID = .unknown
  private var aggregateDeviceID: AudioObjectID = .unknown
  private var deviceProcID: AudioDeviceIOProcID?

  init(processID: pid_t, analyzer: LilithAudioAnalyzer, onFrame: @escaping (AudioFeatureFrame) -> Void) {
    self.processID = processID
    self.analyzer = analyzer
    self.onFrame = onFrame
  }

  func start() -> Bool {
    guard #available(macOS 14.4, *) else { return false }
    guard !aggregateDeviceID.isValid else { return true }
    do {
      try prepareAndRun()
      return true
    } catch {
      Logger.log("Lilith audio tap unavailable: \(error)", level: .warning)
      stop()
      return false
    }
  }

  func stop() {
    if aggregateDeviceID.isValid {
      _ = AudioDeviceStop(aggregateDeviceID, deviceProcID)
      if let deviceProcID {
        _ = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
      }
      _ = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
      aggregateDeviceID = .unknown
      deviceProcID = nil
    }
    if #available(macOS 14.2, *), processTapID.isValid {
      _ = AudioHardwareDestroyProcessTap(processTapID)
      processTapID = .unknown
    }
  }

  deinit {
    stop()
  }

  @available(macOS 14.4, *)
  private func prepareAndRun() throws {
    let processObjectID = try AudioObjectID.translatePIDToProcessObjectID(pid: processID)
    let tapDescription = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
    tapDescription.uuid = UUID()
    tapDescription.muteBehavior = .unmuted

    var tapID = AudioObjectID.unknown
    var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)
    guard err == noErr else { throw LilithAudioTapError("Process tap creation failed: \(err)") }
    processTapID = tapID

    var streamDescription = try tapID.readAudioTapStreamBasicDescription()
    guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
      throw LilithAudioTapError("Audio tap format unavailable.")
    }

    let outputDeviceID = try AudioObjectID.readDefaultSystemOutputDevice()
    let outputUID = try outputDeviceID.readDeviceUID()
    let aggregateUID = UUID().uuidString
    let description: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Lilith Jam Sessions Tap",
      kAudioAggregateDeviceUIDKey: aggregateUID,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [[
        kAudioSubTapDriftCompensationKey: true,
        kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
      ]],
    ]

    aggregateDeviceID = .unknown
    err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
    guard err == noErr else { throw LilithAudioTapError("Aggregate tap device creation failed: \(err)") }

    err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue) { [weak self] _, inputData, _, _, _ in
      guard let self, let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else {
        return
      }
      guard let channel = buffer.floatChannelData?[0] else { return }
      let count = min(Int(buffer.frameLength), 2048)
      let samples = Array(UnsafeBufferPointer(start: channel, count: count))
      onFrame(analyzer.analyze(samples: samples, sampleRate: format.sampleRate, time: CACurrentMediaTime()))
    }
    guard err == noErr else { throw LilithAudioTapError("Audio tap callback creation failed: \(err)") }

    err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
    guard err == noErr else { throw LilithAudioTapError("Audio tap start failed: \(err)") }
  }
}

private struct LilithAudioTapError: LocalizedError {
  let errorDescription: String?

  init(_ message: String) {
    errorDescription = message
  }
}

private extension AudioObjectID {
  static let system = AudioObjectID(kAudioObjectSystemObject)
  static let unknown = kAudioObjectUnknown
  var isValid: Bool { self != .unknown }

  static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
    try system.read(kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
  }

  static func translatePIDToProcessObjectID(pid: pid_t) throws -> AudioObjectID {
    try system.read(
      kAudioHardwarePropertyTranslatePIDToProcessObject,
      defaultValue: AudioObjectID.unknown,
      qualifier: pid
    )
  }

  func readDeviceUID() throws -> String {
    try readString(kAudioDevicePropertyDeviceUID)
  }

  func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
    try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
  }

  func read<T>(_ selector: AudioObjectPropertySelector, defaultValue: T) throws -> T {
    try read(
      AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      ),
      defaultValue: defaultValue
    )
  }

  func read<T, Q>(_ selector: AudioObjectPropertySelector, defaultValue: T, qualifier: Q) throws -> T {
    var qualifier = qualifier
    return try withUnsafeMutablePointer(to: &qualifier) { pointer in
      try read(
        AudioObjectPropertyAddress(
          mSelector: selector,
          mScope: kAudioObjectPropertyScopeGlobal,
          mElement: kAudioObjectPropertyElementMain
        ),
        defaultValue: defaultValue,
        qualifierSize: UInt32(MemoryLayout<Q>.size),
        qualifierData: pointer
      )
    }
  }

  func readString(_ selector: AudioObjectPropertySelector) throws -> String {
    try read(selector, defaultValue: "" as CFString) as String
  }

  func read<T>(
    _ address: AudioObjectPropertyAddress,
    defaultValue: T,
    qualifierSize: UInt32 = 0,
    qualifierData: UnsafeRawPointer? = nil
  ) throws -> T {
    var address = address
    var dataSize: UInt32 = 0
    var err = AudioObjectGetPropertyDataSize(self, &address, qualifierSize, qualifierData, &dataSize)
    guard err == noErr else { throw LilithAudioTapError("Core Audio property size read failed: \(err)") }

    var value = defaultValue
    err = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(self, &address, qualifierSize, qualifierData, &dataSize, pointer)
    }
    guard err == noErr else { throw LilithAudioTapError("Core Audio property read failed: \(err)") }
    return value
  }
}
