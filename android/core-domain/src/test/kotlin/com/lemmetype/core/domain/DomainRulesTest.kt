package com.lemmetype.core.domain

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.minutes

class DomainRulesTest {
    @Test
    fun `the state machine walks a whole dictation and rejects the rest`() {
        val machine = RecorderStateMachine()
        assertFalse(machine.handle(RecorderEvent.StopRequested))
        assertEquals(RecorderState.Idle, machine.state)
        for (event in listOf(RecorderEvent.Activate, RecorderEvent.CaptureStarted, RecorderEvent.StopRequested, RecorderEvent.CaptureFinished)) {
            assertTrue(machine.handle(event))
        }
        assertEquals(RecorderState.Processing, machine.state)
        assertTrue(machine.handle(RecorderEvent.ProcessingNeedsAttention(DictationIssue.ReviewText)))
        assertTrue(machine.state.isFinished)
        assertTrue(machine.handle(RecorderEvent.Retry))
        assertTrue(machine.handle(RecorderEvent.ProcessingFinished))
        assertTrue(machine.handle(RecorderEvent.Reset))
        assertEquals(RecorderState.Idle, machine.state)
    }

    @Test
    fun `capturing states are the ones that may hold the microphone`() {
        assertEquals(
            setOf("preparing", "recording", "stopping"),
            listOf(RecorderState.Idle, RecorderState.Preparing, RecorderState.Recording, RecorderState.Stopping, RecorderState.Processing)
                .filter { it.isCapturing }.map { it.name }.toSet(),
        )
    }

    @Test
    fun `phones stop a recording after five minutes`() {
        assertEquals(5.minutes, RecordingLimits.HANDHELD.maximumDuration)
        assertEquals(null, RecordingLimits.NONE.maximumDuration)
    }

    @Test
    fun `the english-only scope offers only english and english models`() {
        assertTrue(LanguageScope.ENGLISH_ONLY.offers("en-GB"))
        assertFalse(LanguageScope.ENGLISH_ONLY.offers("te-IN"))
        assertFalse(LanguageScope.ENGLISH_ONLY.offers(SpokenLanguages.AUTOMATIC))
        assertEquals(
            listOf("whisper-tiny-en", "whisper-base-en", "whisper-small-en"),
            ModelCatalog.ALL.filter(LanguageScope.ENGLISH_ONLY::lists).map { it.id.rawValue },
        )
        assertEquals(6, ModelCatalog.ALL.count(LanguageScope.ALL_LANGUAGES::lists))
    }

    @Test
    fun `descriptors match a bare language code`() {
        val descriptor = EngineDescriptor(RecognitionEngineId.WHISPER, supportedLanguages = listOf("en"), assets = AssetRequirement.None)
        assertTrue(descriptor.supports("en-IN"))
        assertFalse(descriptor.supports("hi"))
        assertFalse(descriptor.supports(RecognitionNeed("en", RecognitionTask.TRANSLATE_TO_ENGLISH)))
    }

    @Test
    fun `only https on the allowlisted host is a trusted model source`() {
        assertTrue(ModelCatalog.isTrustedSource(ModelCatalog.WHISPER_BASE_ENGLISH.files.single().url))
        assertFalse(ModelCatalog.isTrustedSource("http://huggingface.co/x"))
        assertFalse(ModelCatalog.isTrustedSource("https://huggingface.co.evil.example/x"))
        assertFalse(ModelCatalog.isTrustedSource("https://evil.example@huggingface.co/x"))
        assertTrue(ModelCatalog.isTrustedSource("https://HuggingFace.co:443/x"))
    }

    @Test
    fun `diagnostics keep identifiers and redact everything else`() {
        assertEquals(DiagnosticValue.id("recognition.no-speech"), DiagnosticValue.id("recognition.no-speech"))
        for (unsafe in listOf("Hello there", "", "Ana@example.com", "a".repeat(65), "_leading", "UPPER")) {
            assertEquals(DiagnosticValue.id(DiagnosticValue.REDACTED), DiagnosticValue.id(unsafe), unsafe)
        }
        assertFailsWith<IllegalArgumentException> {
            DiagnosticEvent(0, DiagnosticCategory.RECORDER, "user said hello", emptyMap())
        }
    }

    @Test
    fun `issue identifiers match the Swift names`() {
        assertEquals("review.text", DictationIssue.ReviewText.identifier)
        assertEquals("engine.none-available", DictationIssue.NoEngineAvailable.identifier)
        assertEquals(
            "engine.unsupported.insufficient-memory",
            DictationIssue.EngineUnavailable(RecognitionEngineId.WHISPER, EngineAvailability.Unsupported(UnsupportedReason.INSUFFICIENT_MEMORY)).identifier,
        )
        assertEquals("recognition.silent-audio", DictationIssue.RecognitionFailed(RecognitionError.SilentAudio).identifier)
    }
}
