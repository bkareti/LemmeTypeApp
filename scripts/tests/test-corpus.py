#!/usr/bin/env python3
"""Fixture tests for scripts/corpus.py: no network and no real dataset."""

import hashlib
import importlib.util
import io
import json
import struct
import sys
import tarfile
import tempfile
import unittest
import wave
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("corpus", REPO / "scripts" / "corpus.py")
corpus = importlib.util.module_from_spec(spec)
sys.modules["corpus"] = corpus
spec.loader.exec_module(corpus)


def write_wav(path: Path, seconds: float, rate: int = 16_000, channels: int = 1) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as audio:
        audio.setnchannels(channels)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes(b"\x01\x00" * int(seconds * rate) * channels)


def tsv_line(sentence: str, file: str, raw: str, gender: str = "FEMALE") -> str:
    return "\t".join([sentence, file, raw, raw.lower(), "x", "16000", gender]) + "\n"


class FleursFixture(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-corpus-")
        self.root = Path(self.tmp.name) / "fleurs" / corpus.FLEURS_REVISION
        (self.root / "en_us").mkdir(parents=True)
        (self.root / "en_us" / "test.tsv").write_text(
            tsv_line("10", "e1.wav", "I will come tomorrow.") + tsv_line("11", "e2.wav", "Gate 23 closes.", "MALE"),
            encoding="utf-8",
        )
        (self.root / "en_us" / "dev.tsv").write_text(tsv_line("12", "e3.wav", "Never mind."), encoding="utf-8")
        (self.root / "hi_in").mkdir()
        (self.root / "hi_in" / "test.tsv").write_text(
            tsv_line("10", "h1.wav", "मैं कल आऊँगा।")
            + tsv_line("10", "h2.wav", "मैं कल आऊँगा।", "MALE")
            + tsv_line("12", "h3.wav", "कोई बात नहीं।")
            + tsv_line("99", "h4.wav", "बिना अंग्रेज़ी।"),
            encoding="utf-8",
        )
        for name, seconds in [("e1", 1.5), ("e2", 2.0), ("e3", 1.0)]:
            write_wav(self.root / "en_us" / "audio" / "test" / f"{name}.wav", seconds)
        for name in ["h1", "h2", "h3", "h4"]:
            write_wav(self.root / "hi_in" / "audio" / "test" / f"{name}.wav", 1.25)

    def tearDown(self) -> None:
        self.tmp.cleanup()


class BuildFleursTests(FleursFixture):
    def build(self, per_language: int = 10) -> dict:
        return corpus.build_fleurs(self.root, ["en_us", "hi_in"], per_language, [])

    def test_cases_carry_human_references_checksums_and_durations(self) -> None:
        manifest = self.build()
        self.assertEqual(corpus.manifest_problems(manifest, self.root), [])
        cases = {case["id"]: case for case in manifest["cases"]}
        hindi = cases["fleurs-hi_in-h1"]
        self.assertEqual(hindi["language"], "hi")
        self.assertEqual(hindi["reference"], "मैं कल आऊँगा।")
        self.assertEqual(hindi["englishReference"], "I will come tomorrow.")
        self.assertEqual(hindi["review"], "dataset-human")
        self.assertEqual(hindi["audio"]["seconds"], 1.25)
        self.assertEqual(hindi["audio"]["path"], "hi_in/audio/test/h1.wav")
        self.assertEqual(hindi["audio"]["sha256"], corpus.sha256_of(self.root / "hi_in/audio/test/h1.wav"))
        self.assertEqual(manifest["sources"][0]["license"], "CC-BY-4.0")

    def test_english_references_come_from_any_split_and_are_never_invented(self) -> None:
        cases = {case["id"]: case for case in self.build()["cases"]}
        self.assertEqual(cases["fleurs-hi_in-h3"]["englishReference"], "Never mind.")
        self.assertIsNone(cases["fleurs-hi_in-h4"]["englishReference"])
        self.assertIn("no-english-reference", cases["fleurs-hi_in-h4"]["tags"])
        self.assertIsNone(cases["fleurs-en_us-e1"]["englishReference"])

    def test_numbers_and_gender_are_tagged(self) -> None:
        cases = {case["id"]: case for case in self.build()["cases"]}
        self.assertIn("numbers", cases["fleurs-en_us-e2"]["tags"])
        self.assertIn("male", cases["fleurs-en_us-e2"]["tags"])
        self.assertNotIn("numbers", cases["fleurs-en_us-e1"]["tags"])

    def test_selection_is_deterministic_and_covers_every_sentence_before_repeating_one(self) -> None:
        first = [case["id"] for case in self.build(per_language=3)["cases"] if case["language"] == "hi"]
        again = [case["id"] for case in self.build(per_language=3)["cases"] if case["language"] == "hi"]
        self.assertEqual(first, again)
        self.assertEqual(len(first), 3)
        # Sentences 10, 12, and 99 each appear once before sentence 10 is used twice.
        self.assertEqual(len([name for name in first if name in ("fleurs-hi_in-h1", "fleurs-hi_in-h2")]), 1)

    def test_float_samples_are_read_like_fleurs_stores_them(self) -> None:
        path = self.root / "hi_in" / "audio" / "test" / "h1.wav"
        samples = 24_000
        data = b"\x00\x00\x00\x00" * samples
        fmt = struct.pack("<HHIIHH", 3, 1, 16_000, 64_000, 4, 32)
        body = b"WAVE" + b"fmt " + struct.pack("<I", 16) + fmt + b"data" + struct.pack("<I", len(data)) + data
        path.write_bytes(b"RIFF" + struct.pack("<I", len(body)) + body)
        cases = {case["id"]: case for case in self.build()["cases"]}
        self.assertEqual(cases["fleurs-hi_in-h1"]["audio"]["seconds"], 1.5)

    def test_audio_that_is_not_16_khz_mono_is_refused(self) -> None:
        write_wav(self.root / "hi_in" / "audio" / "test" / "h1.wav", 1, rate=8_000)
        with self.assertRaises(SystemExit):
            self.build()

    def test_a_transcript_without_its_recording_is_refused(self) -> None:
        (self.root / "hi_in" / "audio" / "test" / "h2.wav").unlink()
        with self.assertRaises(SystemExit):
            self.build()

    def test_a_changed_recording_fails_verification(self) -> None:
        manifest = self.build()
        write_wav(self.root / "hi_in" / "audio" / "test" / "h1.wav", 2.0)
        problems = corpus.manifest_problems(manifest, self.root)
        self.assertEqual(problems, ["fleurs-hi_in-h1: hi_in/audio/test/h1.wav does not match its SHA-256"])


class ManifestRuleTests(unittest.TestCase):
    def manifest(self, **changes) -> dict:
        case = {
            "id": "a",
            "source": "s",
            "language": "en-US",
            "audio": {"path": "x/a.wav", "sha256": "0" * 64, "seconds": 1},
            "reference": "hello",
            "englishReference": None,
            "category": "read",
            "tags": [],
            "review": "dataset-human",
        }
        case.update(changes)
        source = {"id": "s", "title": "S", "license": "CC0-1.0", "licenseURL": "u", "url": "u", "revision": "r",
                  "attribution": "a"}
        return {"schema": 1, "name": "t", "sources": [source], "cases": [case], "generated": [], "variants": []}

    def test_a_good_manifest_passes(self) -> None:
        self.assertEqual(corpus.manifest_problems(self.manifest()), [])

    def test_each_rule(self) -> None:
        self.assertIn("a: unknown source t", corpus.manifest_problems(self.manifest(source="t")))
        self.assertIn("a: a recording needs a human reference", corpus.manifest_problems(self.manifest(reference="")))
        self.assertIn(
            "a: audio path must stay inside the corpus root",
            corpus.manifest_problems(self.manifest(audio={"path": "../a.wav", "sha256": "0" * 64, "seconds": 1})),
        )
        self.assertIn(
            "a: sha256 is not 64 hex digits",
            corpus.manifest_problems(self.manifest(audio={"path": "a.wav", "sha256": "ABC", "seconds": 1})),
        )
        self.assertIn("a: unknown review guessed", corpus.manifest_problems(self.manifest(review="guessed")))
        doubled = self.manifest()
        doubled["cases"].append(dict(doubled["cases"][0]))
        self.assertIn("duplicate id a", corpus.manifest_problems(doubled))

    def test_variant_rules_match_the_swift_ones(self) -> None:
        self.assertEqual(corpus.variant_problems({"transform": "speed", "factor": 0.9}), [])
        self.assertEqual(corpus.variant_problems({"transform": "speed", "factor": 1}), ["speed needs a factor in 0.5…2, not 1"])
        self.assertEqual(corpus.variant_problems({"transform": "noise", "snrDecibels": 10}), ["noise needs snrDecibels and seed"])
        self.assertEqual(corpus.variant_problems({"transform": "clip", "gain": 1}), ["clip needs a gain above 1"])
        self.assertEqual(corpus.variant_problems({"transform": "pad"}), ["pad needs a positive leading or trailing"])
        self.assertEqual(corpus.variant_problems({"transform": "repeat", "count": 11}), ["repeat needs a count in 2…10"])
        self.assertEqual(corpus.variant_problems({"transform": "warp"}), ["unknown transform warp"])

    def test_the_committed_manifests_pass(self) -> None:
        for path in sorted((REPO / "docs" / "testing" / "corpus").glob("*.json")):
            with self.subTest(path.name):
                self.assertEqual(corpus.manifest_problems(json.loads(path.read_text(encoding="utf-8"))), [])


class FetchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-fetch-")
        self.cache = Path(self.tmp.name)
        transcript = tsv_line("1", "a.wav", "hello").encode()
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w:gz") as tar:
            data = io.BytesIO()
            with wave.open(data, "wb") as audio:
                audio.setnchannels(1)
                audio.setsampwidth(2)
                audio.setframerate(16_000)
                audio.writeframes(b"\x00\x00" * 160)
            member = tarfile.TarInfo("test/a.wav")
            member.size = len(data.getvalue())
            tar.addfile(member, io.BytesIO(data.getvalue()))
        self.served = {"en_us/test.tsv": transcript, "en_us/audio/test.tar.gz": archive.getvalue()}
        pins = {
            "en_us/test.tsv": (len(transcript), hashlib.sha1(b"blob %d\0" % len(transcript) + transcript).hexdigest()),
            "en_us/audio/test.tar.gz": (len(archive.getvalue()), hashlib.sha256(archive.getvalue()).hexdigest()),
        }
        self.pins = mock.patch.dict(corpus.FLEURS_FILES, pins, clear=True)
        self.pins.start()
        self.requests: list[str] = []

    def tearDown(self) -> None:
        self.pins.stop()
        self.tmp.cleanup()

    def opener(self, url: str):
        self.requests.append(url)
        path = url.split("/data/", 1)[1]
        return io.BytesIO(self.served[path])

    def test_without_yes_nothing_is_downloaded(self) -> None:
        with mock.patch("sys.stdout", io.StringIO()):
            self.assertEqual(corpus.fetch(self.cache, ["en_us"], yes=False, opener=self.opener), 0)
        self.assertEqual(self.requests, [])

    def test_downloads_verify_extract_and_are_not_repeated(self) -> None:
        with mock.patch("sys.stdout", io.StringIO()):
            self.assertEqual(corpus.fetch(self.cache, ["en_us"], yes=True, opener=self.opener), 0)
        root = corpus.corpus_root(self.cache)
        self.assertTrue((root / "en_us/test.tsv").is_file())
        self.assertTrue((root / "en_us/audio/test/a.wav").is_file())
        self.assertFalse((root / "en_us/audio/test.tar.gz").exists())
        self.assertTrue(all(corpus.FLEURS_REVISION in url for url in self.requests))
        self.requests.clear()
        with mock.patch("sys.stdout", io.StringIO()):
            self.assertEqual(corpus.fetch(self.cache, ["en_us"], yes=True, opener=self.opener), 0)
        self.assertEqual(self.requests, [])

    def test_a_file_that_does_not_match_its_pin_is_deleted(self) -> None:
        self.served["en_us/test.tsv"] = b"tampered\n"
        with mock.patch("sys.stdout", io.StringIO()), mock.patch("sys.stderr", io.StringIO()):
            self.assertEqual(corpus.fetch(self.cache, ["en_us"], yes=True, opener=self.opener), 1)
        root = corpus.corpus_root(self.cache)
        self.assertEqual(list((root / "en_us").glob("test.tsv*")), [])

    def test_an_archive_cannot_write_outside_its_folder(self) -> None:
        archive = self.cache / "evil.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            member = tarfile.TarInfo("../escaped.txt")
            member.size = 1
            tar.addfile(member, io.BytesIO(b"x"))
        target = self.cache / "inside"
        target.mkdir()
        with self.assertRaises(tarfile.TarError):
            corpus.safe_extract(archive, target)
        self.assertFalse((self.cache / "escaped.txt").exists())


if __name__ == "__main__":
    unittest.main()
