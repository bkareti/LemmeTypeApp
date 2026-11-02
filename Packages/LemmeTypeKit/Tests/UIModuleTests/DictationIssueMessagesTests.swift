import Domain
import Testing

@testable import UI

struct DictationIssueMessagesTests {
    @Test func aSilentMicrophoneIsNotReportedAsNoSpeech() {
        let silent = DictationIssue.recognitionFailed(.silentAudio).userMessage
        let noSpeech = DictationIssue.recognitionFailed(.noSpeechDetected).userMessage

        #expect(silent != noSpeech)
        #expect(silent.localizedCaseInsensitiveContains("microphone"))
        #expect(!noSpeech.localizedCaseInsensitiveContains("microphone"))
    }
}
