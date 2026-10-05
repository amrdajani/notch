import AVFoundation
import Speech

enum MediaPermissions {
    static func speech() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func microphone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    continuation.resume(returning: allowed)
                }
            }
        default:
            return false
        }
    }
}

enum AudioCapture {
    static func start(_ engine: AVAudioEngine, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let hardware = input.outputFormat(forBus: 0)
        let format: AVAudioFormat? = hardware.sampleRate > 0 ? hardware : nil
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    static func stop(_ engine: AVAudioEngine) {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }
}
