#!/usr/bin/env python3
"""Tests for scripts/cloud-speech-eval.py. The scoring cases are the ones the Swift
TranscriptMetricsTests, NumberNormalizerTests, and TranslationAndStyleScoreTests check, so
cloud and local engines are scored by the same rules. No test touches the network."""

import argparse
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cloud_speech_eval", REPO / "scripts" / "cloud-speech-eval.py")
tool = importlib.util.module_from_spec(spec)
sys.modules["cloud_speech_eval"] = tool
spec.loader.exec_module(tool)


class ScoringMatchesSwift(unittest.TestCase):
    def test_normalizer(self):
        self.assertEqual(tool.words("Don’t ship it, OK?"), ["don't", "ship", "it", "ok"])
        self.assertEqual(tool.normalize("  Ship   it.  "), "ship it")
        self.assertEqual(tool.normalize("…"), "")
        self.assertEqual(tool.normalize("café"), tool.normalize("café"))
        self.assertEqual(tool.words("क्‌ष"), tool.words("क्ष"))
        self.assertEqual(tool.words("मैं कल आऊँगा।"), ["मैं", "कल", "आऊँगा"])
        self.assertEqual(tool.words("నేను రేపు వస్తాను."), ["నేను", "రేపు", "వస్తాను"])
        self.assertEqual(tool.words("ನಾನು ನಾಳೆ ಬರುತ್ತೇನೆ"), ["ನಾನು", "ನಾಳೆ", "ಬರುತ್ತೇನೆ"])
        self.assertEqual(tool.words("நான் நாளை வருவேன்"), ["நான்", "நாளை", "வருவேன்"])
        self.assertEqual(tool.words("१२ बजे"), ["१२", "बजे"])

    def test_alignment(self):
        alignment = tool.align(["a", "b", "c", "d"], ["a", "x", "c", "d", "e"])
        self.assertEqual(alignment, {"deletions": 0, "insertions": 1, "referenceLength": 4, "substitutions": 1})
        self.assertEqual(tool.error_rate(alignment), 0.5)
        self.assertEqual(tool.align(["a", "b", "c"], ["a"])["deletions"], 2)

    def test_word_and_character_error_rates(self):
        wer = lambda reference, hypothesis: tool.error_rate(tool.align(tool.words(reference), tool.words(hypothesis)))
        cer = lambda reference, hypothesis: tool.error_rate(
            tool.align(list(tool.normalize(reference)), list(tool.normalize(hypothesis))))
        self.assertEqual(wer("Ship it on Wednesday.", "ship it on wednesday"), 0)
        self.assertEqual(wer("I don't know", "I don’t know"), 0)
        self.assertEqual(wer("a b c d", "a x c d"), 0.25)
        self.assertEqual(wer("a b c d", "a b c d e"), 0.25)
        self.assertEqual(wer("a b c d", "a c d"), 0.25)
        self.assertEqual(wer("", ""), 0)
        self.assertEqual(wer("", "noise"), 1)
        self.assertEqual(cer("kitten", "sitting"), 0.5)
        self.assertAlmostEqual(cer("a b", "ab"), 1 / 3)
        self.assertEqual(cer("", "x"), 1)

    def test_numbers(self):
        for spoken, digits in [("twenty-three people", "23 people"), ("one hundred and five", "105"),
                               ("Two thousand twenty four", "2024"), ("three million", "3000000"),
                               ("nineteen eleven", "1911"), ("in twenty twenty-four", "in 2024"),
                               ("twelve hundred", "1200"), ("zero", "0"), ("one", "1")]:
            self.assertEqual(tool.normalize_numbers(spoken), digits, spoken)
        self.assertEqual(tool.normalize_numbers("१२ बजे"), "12 बजे")
        self.assertEqual(tool.normalize_numbers("౧౯౧౧"), "1911")
        self.assertEqual(tool.normalize_numbers("1,000 and 12,50"), "1000 and 12,50")
        for unchanged in ["five six seven", "someone and anyone", "hundred", "नमस्ते"]:
            self.assertEqual(tool.normalize_numbers(unchanged), unchanged)
        self.assertEqual(tool.normalize_numbers("Gate Ten closes, OK?"), "Gate 10 closes, OK?")

    def test_repetition_and_silence(self):
        self.assertFalse(tool.score("no no no", "no, no, no")["repetitionLoop"])
        self.assertFalse(tool.score("very good", "very very good")["repetitionLoop"])
        self.assertTrue(tool.score("go", "go go go go")["repetitionLoop"])
        self.assertTrue(tool.score("", "thank you")["textWithoutSpeech"])

    def test_chrf(self):
        statistics = tool.character_ngrams("the cat", "the hat")
        self.assertEqual(statistics["matches"], [5, 3, 1, 0, 0, 0])
        self.assertEqual(statistics["reference"], [6, 5, 4, 3, 2, 1])
        self.assertAlmostEqual(tool.chrf(statistics), 100 * (5 / 6 + 3 / 5 + 1 / 4) / 6)
        self.assertEqual(tool.chrf(tool.character_ngrams("Ship it.", "Ship it.")), 100)
        self.assertEqual(tool.chrf(tool.character_ngrams("", "")), 100)
        self.assertEqual(tool.chrf(tool.character_ngrams("ship", "")), 0)


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


class Requests(unittest.TestCase):
    def test_bodhan_request_shape(self):
        url, parts = tool.PROVIDERS["bodhan"].request("k", b"RIFF", "a.wav", "te", "transcribe", "native")
        self.assertEqual(url, "https://api.bodhan.ai/v1/audio/transcriptions")
        self.assertEqual(parts["headers"]["Authorization"], "Bearer k")
        self.assertIn(b'name="language"\r\n\r\nte\r\n', parts["body"])
        self.assertIn(b'name="model"\r\n\r\nindic-transcribe\r\n', parts["body"])

    def test_sarvam_request_shape(self):
        provider = tool.PROVIDERS["sarvam"]
        url, parts = provider.request("k", b"RIFF", "a.wav", "hi", "translate", "native")
        self.assertEqual(url, "https://api.sarvam.ai/speech-to-text")
        self.assertEqual(parts["headers"]["api-subscription-key"], "k")
        self.assertIn(b'name="mode"\r\n\r\ntranslate\r\n', parts["body"])
        self.assertIn(b'name="language_code"\r\n\r\nhi-IN\r\n', parts["body"])
        _, parts = provider.request("k", b"RIFF", "a.wav", "te", "transcribe", "codemix")
        self.assertIn(b'name="mode"\r\n\r\ncodemix\r\n', parts["body"])
        self.assertEqual(provider.label("codemix"), "sarvam-saaras-v4-codemix")

    def test_rate_limits_are_retried_and_client_errors_are_not(self):
        calls = []

        def flaky(request, timeout):
            calls.append(request)
            if len(calls) == 1:
                raise urllib.error.HTTPError(request.full_url, 429, "", {}, io.BytesIO(b"{}"))
            return Response(json.dumps({"text": "నమస్తే"}).encode())

        text, _, _ = tool.send(tool.PROVIDERS["bodhan"], "k", b"x", "a.wav", "te", "transcribe", "native",
                               opener=flaky, sleep=lambda _: None)
        self.assertEqual(text, "నమస్తే")
        self.assertEqual(len(calls), 2)

        def refused(request, timeout):
            raise urllib.error.HTTPError(request.full_url, 401, "", {},
                                         io.BytesIO(b'{"error": {"code": "invalid_api_key_error", "message": "k"}}'))

        with self.assertRaises(tool.ProviderError) as context:
            tool.send(tool.PROVIDERS["bodhan"], "k", b"x", "a.wav", "te", "transcribe", "native", opener=refused,
                      sleep=lambda _: None)
        self.assertEqual(context.exception.code, "http-401")
        self.assertNotIn("k\"", str(context.exception))


class Keys(unittest.TestCase):
    def test_environment_then_private_file(self):
        with tempfile.TemporaryDirectory(prefix="LemmeTypeTests-") as folder:
            path = Path(folder) / "cloud-eval.env"
            self.assertEqual(tool.api_key("X_KEY", {"X_KEY": "env"}, path), "env")
            self.assertIsNone(tool.api_key("X_KEY", {"X_KEY": "..."}, path))
            path.write_text("export X_KEY='file'\nOTHER=1\n")
            os.chmod(path, 0o600)
            self.assertEqual(tool.api_key("X_KEY", {}, path), "file")
            os.chmod(path, 0o644)
            with self.assertRaises(SystemExit):
                tool.api_key("X_KEY", {}, path)


class EndToEnd(unittest.TestCase):
    def test_run_writes_a_report_without_text_and_compare_pairs_cases(self):
        with tempfile.TemporaryDirectory(prefix="LemmeTypeTests-") as folder:
            folder = Path(folder)
            root = folder / "audio"
            root.mkdir()
            cases = []
            for index, (language, reference) in enumerate([("te", "నేను రేపు వస్తాను"), ("hi", "मैं कल आऊँगा")]):
                audio = root / f"{index}.wav"
                audio.write_bytes(b"RIFF" + bytes([index]))
                cases.append({"id": f"case-{index}", "source": "fleurs", "language": language,
                              "audio": {"path": audio.name, "sha256": hashlib.sha256(audio.read_bytes()).hexdigest(),
                                        "seconds": 3.0},
                              "reference": reference, "englishReference": "I will come tomorrow", "category": "read",
                              "tags": ["fleurs"], "review": "dataset-human"})
            manifest = folder / "manifest.json"
            manifest.write_text(json.dumps({"schema": 1, "name": "test", "cases": cases}), encoding="utf-8")
            answers = {"0.wav": "నేను రేపు వస్తాను", "1.wav": "मैं कल आया"}

            def opener(request, timeout):
                name = request.data.split(b'filename="')[1].split(b'"')[0].decode()
                return Response(json.dumps({"text": answers[name]}, ensure_ascii=False).encode())

            out = folder / "out"
            args = argparse.Namespace(provider="bodhan", task="transcribe", output="native", languages=None,
                                      limit=None, manifest=manifest, root=root, out=out, workers=1,
                                      reference_field="reference",
                                      allow_failures=False, yes=True)
            with mock.patch.object(tool, "ANSWERS", folder / "answers"), \
                    mock.patch.dict(os.environ, {"BODHAN_API_KEY": "test-key"}), \
                    mock.patch("sys.stdout", io.StringIO()):
                self.assertEqual(tool.run(args, opener=opener), 0)
                dry = argparse.Namespace(**{**vars(args), "yes": False})
                self.assertEqual(tool.run(dry, opener=lambda *a, **k: self.fail("uploaded without --yes")), 0)
            report_file = out / "bodhan-indic-transcribe-transcribe-exact.json"
            text = report_file.read_text(encoding="utf-8")
            self.assertNotIn("వస్తాను", text, "reports hold metrics only")
            self.assertNotIn("test-key", text)
            report = json.loads(text)
            self.assertEqual(report["schema"], 2)
            by_id = {run["id"]: run["result"]["score"]["words"] for run in report["runs"]}
            self.assertEqual(by_id["case-0"]["substitutions"], 0)
            self.assertEqual(by_id["case-1"]["substitutions"], 1)

            rows = tool.compare_rows([report])
            self.assertEqual({row["language"]: row["runs"] for row in rows}, {"hi": 1, "te": 1})
            self.assertEqual(next(row for row in rows if row["language"] == "te")["wer"], 0)


class CodeMixAndFailures(unittest.TestCase):
    def test_english_kept_counts_only_english_letters(self):
        reference = "రేపు team meeting ఉంది, team రండి"
        self.assertEqual(tool.english_kept(reference, "రేపు Team meeting ఉంది"), {"englishWords": 3, "kept": 2})
        self.assertEqual(tool.english_kept(reference, "రేపు టీమ్ మీటింగ్ ఉంది")["kept"], 0)

    @staticmethod
    def run_with(case_id, outcome, substitutions):
        words = {"deletions": 0, "insertions": 0, "referenceLength": 4, "substitutions": substitutions}
        return {"id": case_id, "review": "dataset-human", "result": {
            "language": "te", "outcome": outcome, "producedText": outcome == "delivered", "stopToDeliverySeconds": 1.0,
            "score": {"words": words, "characters": words, "numberNormalizedWords": words}}}

    def test_failed_requests_are_counted_apart_and_cases_are_paired(self):
        first = {"label": "a", "mode": "exact", "task": "transcribe", "runs": [
            self.run_with("1", "delivered", 0), self.run_with("2", "http-429", 4)]}
        second = {"label": "b", "mode": "exact", "task": "transcribe", "runs": [
            self.run_with("1", "delivered", 1), self.run_with("2", "delivered", 4)]}
        rows = {row["label"]: row for row in tool.compare_rows([first, second])}
        self.assertEqual(rows["a"]["runs"], 1)
        self.assertEqual(rows["a"]["wer"], 0)
        self.assertEqual(rows["a"]["failed"], 1)
        self.assertEqual(rows["b"]["wer"], 0.25, "case 2 failed on a, so b is not scored on it either")
        self.assertEqual(rows["b"]["failed"], 0)


if __name__ == "__main__":
    unittest.main()
