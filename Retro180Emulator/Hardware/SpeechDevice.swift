import AVFoundation
import Foundation

// MARK: - Speech Device (High Level ASCII)
// Replaces SP0256 low-level emulation with a direct Text-to-Speech port.
public class SpeechDevice: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var buffer: String = ""

    // Voice Management
    public private(set) var availableVoices: [AVSpeechSynthesisVoice]
    public var currentVoiceIdentifier: String

    // Recording State
    private let recordingSynthesizer = AVSpeechSynthesizer()
    private var recordingFile: AVAudioFile?
    private var recordingUrl: URL?
    public var isRecording: Bool = false

    public var isSpeaking: Bool {
        return synthesizer.isSpeaking
    }

    public override init() {
        // smart deduplication mechanism
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let grouped = Dictionary(grouping: allVoices, by: { $0.name })

        var uniqueVoices: [AVSpeechSynthesisVoice] = []
        for (_, voices) in grouped {
            // Select the highest quality voice (Premium > Enhanced > Default)
            if let best = voices.sorted(by: { $0.quality.rawValue > $1.quality.rawValue }).first {
                uniqueVoices.append(best)
            }
        }

        self.availableVoices = uniqueVoices.sorted(by: { $0.name < $1.name })

        // Default to Alex or first en-US
        if let alex = self.availableVoices.first(where: {
            $0.identifier == "com.apple.speech.voice.Alex"
        }) {
            self.currentVoiceIdentifier = alex.identifier
        } else {
            self.currentVoiceIdentifier =
                AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? ""
        }

        super.init()
        synthesizer.delegate = self
    }

    /// Write ASCII byte to buffer. Trigger speech on Carriage Return (0x0D).
    public func write(byte: UInt8) {
        // Check for Carriage Return (13) to trigger speech
        if byte == 0x0D {
            if !buffer.isEmpty {
                speak(text: buffer)
                buffer = ""
            }
            return
        }

        // Filter for printable characters or standard text
        // We'll accept anything >= 32 (Space) or specific controls if needed.
        // For simplicity, anything valid.
        let scalar = UnicodeScalar(byte)
        if Character(scalar).isASCII {
            buffer.append(Character(scalar))
        }
    }

    public func startRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".wav")
        self.recordingUrl = tempURL
        self.recordingFile = nil
        self.isRecording = true
        print("SpeechDevice: Recording started at \(tempURL.path)")
    }

    public func stopRecording() -> URL? {
        self.isRecording = false
        self.recordingFile = nil
        print("SpeechDevice: Recording stopped")
        return self.recordingUrl
    }

    private func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)

        if let voice = AVSpeechSynthesisVoice(identifier: currentVoiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = 0.5
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        print("SpeechDevice: Spoken '\(text)' using \(utterance.voice?.name ?? "Default")")

        if isRecording {
            let recordingUtterance = AVSpeechUtterance(string: text)
            recordingUtterance.voice = utterance.voice
            recordingUtterance.rate = utterance.rate
            recordingUtterance.volume = utterance.volume

            recordingSynthesizer.write(recordingUtterance) { [weak self] buffer in
                guard let self = self, let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }
                do {
                    if self.recordingFile == nil {
                        guard let url = self.recordingUrl else { return }
                        let settings = pcmBuffer.format.settings
                        self.recordingFile = try AVAudioFile(forWriting: url, settings: settings)
                    }
                    try self.recordingFile?.write(from: pcmBuffer)
                } catch {
                    print("SpeechDevice: Error writing audio buffer: \(error)")
                }
            }
        }
    }

    /// Read Status (Bit 7 = Ready). 0 = Busy Speaking, 1 = Ready.
    public func readStatus() -> UInt8 {
        return isSpeaking ? 0x00 : 0x80
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        // finished
    }
}
