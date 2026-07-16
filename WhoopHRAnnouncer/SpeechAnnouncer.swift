import Foundation
import AVFoundation

final class SpeechAnnouncer: NSObject, AVSpeechSynthesizerDelegate {
    var onAudioSessionStatus: ((String?) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func prepare(audioMode: OtherAudioMode) {
        let audioSession = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = audioMode == .duck
            ? [.duckOthers]
            : [.mixWithOthers]

        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: options)
            onAudioSessionStatus?(nil)
        } catch {
            onAudioSessionStatus?("Audio setup failed: \(error.localizedDescription)")
        }
    }

    func speak(_ text: String, audioMode: OtherAudioMode) {
        if synthesizer.isSpeaking {
            currentUtterance = nil
            synthesizer.stopSpeaking(at: .immediate)
        }

        prepare(audioMode: audioMode)
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            onAudioSessionStatus?(nil)
        } catch {
            onAudioSessionStatus?("Audio playback failed: \(error.localizedDescription)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        deactivateAudioSession()
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
