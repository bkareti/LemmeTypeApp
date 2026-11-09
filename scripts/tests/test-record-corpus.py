#!/usr/bin/env python3
"""Tests for scripts/record-corpus.py and the committed reading scripts. No microphone needed."""

import importlib.util
import json
import struct
import sys
import tempfile
import unicodedata
import unittest
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, REPO / "scripts" / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


tool = load("record_corpus", "record-corpus.py")
corpus = load("corpus_tool", "corpus.py")


def write_wave(path: Path, seconds: float, amplitude: int, rate: int = 16_000) -> None:
    with wave.open(str(path), "wb") as clip:
        clip.setnchannels(1)
        clip.setsampwidth(2)
        clip.setframerate(rate)
        clip.writeframes(struct.pack("<h", amplitude) * int(seconds * rate))


def scripts(text: str) -> set[str]:
    found = set()
    for char in text:
        if char.isalpha():
            found.add("telugu" if "TELUGU" in unicodedata.name(char) else "latin" if char.isascii() else "other")
    return found


class ReadingScript(unittest.TestCase):
    prompts = tool.load_prompts(tool.DEFAULT_PROMPTS)

    def test_ids_are_unique(self):
        ids = [prompt["id"] for prompt in self.prompts]
        self.assertEqual(len(ids), len(set(ids)))

    def test_mixed_sentences_hold_both_scripts_and_a_native_form(self):
        mixed = [prompt for prompt in self.prompts if prompt["language"] == "te"]
        self.assertEqual(len(mixed), 24)
        for prompt in mixed:
            self.assertEqual(scripts(prompt["reference"]), {"telugu", "latin"}, prompt["id"])
            self.assertEqual(scripts(prompt["referenceNative"]), {"telugu"}, prompt["id"])
            self.assertEqual(scripts(prompt["englishReference"]), {"latin"}, prompt["id"])

    def test_english_sentences_are_only_english(self):
        english = [prompt for prompt in self.prompts if prompt["language"] == "en"]
        self.assertEqual(len(english), 10)
        for prompt in english:
            self.assertEqual(scripts(prompt["reference"]), {"latin"}, prompt["id"])

    def test_no_digits(self):
        for prompt in self.prompts:
            self.assertFalse(any(char.isdigit() for char in prompt["reference"]), prompt["id"])


class Recording(unittest.TestCase):
    def test_problems(self):
        self.assertIsNone(tool.clip_problem(3, 0.5))
        self.assertIn("short", tool.clip_problem(0.1, 0.5))
        self.assertIn("30", tool.clip_problem(31, 0.5))
        self.assertIn("silent", tool.clip_problem(3, 0.001))

    def test_audio_facts_and_wrong_format(self):
        with tempfile.TemporaryDirectory(prefix="LemmeTypeTests-") as folder:
            good = Path(folder) / "good.wav"
            write_wave(good, 2, 16384)
            seconds, peak = tool.audio_facts(good)
            self.assertEqual(seconds, 2)
            self.assertAlmostEqual(peak, 0.5)
            wrong = Path(folder) / "wrong.wav"
            write_wave(wrong, 1, 16384, rate=44_100)
            with self.assertRaises(ValueError):
                tool.audio_facts(wrong)

    def test_manifest_holds_only_recorded_clips_and_passes_corpus_verification(self):
        prompts = tool.load_prompts(tool.DEFAULT_PROMPTS)
        with tempfile.TemporaryDirectory(prefix="LemmeTypeTests-") as folder:
            root = Path(folder)
            (root / "audio").mkdir()
            write_wave(root / "audio" / "te-en-m01.wav", 3, 16384)
            write_wave(root / "audio" / "te-en-e01.wav", 3, 16384)
            tool.write_manifest(prompts, root, "2026-11-09")
            manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual([case["id"] for case in manifest["cases"]], ["te-en-m01", "te-en-e01"])
            self.assertEqual(manifest["cases"][0]["tags"], ["consented", "code-mixed"])
            self.assertEqual(manifest["cases"][1]["tags"], ["consented", "english"])
            self.assertEqual(manifest["sources"][0]["uploadHosts"], tool.UPLOAD_HOSTS)
            self.assertEqual(corpus.manifest_problems(manifest, root), [])
            self.assertEqual((root / "manifest.json").stat().st_mode & 0o077, 0)


if __name__ == "__main__":
    unittest.main()
