import AVFoundation
import Foundation
import Speech

@MainActor
@Observable
final class VoiceListener {
    private(set) var isListening = false
    var transcript = ""
    var errorMessage: String?

    private let recognizer = SFSpeechRecognizer()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let engine = AVAudioEngine()

    func toggle() async {
        if isListening {
            stop()
            return
        }
        await start()
    }

    func start() async {
        errorMessage = nil
        transcript = ""

        let speechStatus = await MediaPermissions.speech()
        guard speechStatus == .authorized else {
            errorMessage = "Allow speech recognition to dictate into the notch."
            return
        }

        guard await MediaPermissions.microphone() else {
            errorMessage = "Allow the microphone to dictate into the notch."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil, self.isListening {
                    self.stop()
                }
            }
        }

        do {
            try AudioCapture.start(engine) { buffer in
                request.append(buffer)
            }
            isListening = true
        } catch {
            teardownAudio()
            errorMessage = "Could not start the microphone."
        }
    }

    func stop() {
        guard isListening || request != nil else { return }
        request?.endAudio()
        teardownAudio()
        isListening = false
    }

    private func teardownAudio() {
        AudioCapture.stop(engine)
        task?.cancel()
        task = nil
        request = nil
    }
}
