#!/usr/bin/env python3
"""Evaluation corpus tools (docs/testing/corpus/README.md).

  scripts/corpus.py fetch [--cache DIR] [--languages en_us,hi_in,...] [--yes]
      Download the pinned FLEURS test split. Without --yes it only prints what it would
      download, how big it is, and the licence. Every file is checked against the
      checksum pinned below before it is used.

  scripts/corpus.py build-fleurs [--cache DIR] [--per-language N] [--out FILE]
      Write the FLEURS manifest from a fetched copy: human references from the dataset,
      English references joined by sentence id, SHA-256 and duration of every recording.

  scripts/corpus.py verify FILE... [--root DIR]
      Check manifests (schema, ids, licences, references); with --root also every
      recording's SHA-256.

Audio is kept in the cache, never in the repository (`make privacy-check` fails on
audio files in the repository). Standard library only; run with `python3 -I`.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import sys
import tarfile
import struct
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_CACHE = Path.home() / "Library" / "Caches" / "LemmeTypeCorpus"
DEFAULT_OUT = REPO / "docs" / "testing" / "corpus" / "fleurs.json"
DEFAULT_VARIANTS = REPO / "docs" / "testing" / "corpus" / "variants.json"
SCHEMA = 1
SPEECH_SAMPLE_RATE = 16_000
# WAVE format tags: integer PCM, IEEE float, and the extensible header.
WAVE_FORMATS = {1, 3, 0xFFFE}

# google/fleurs on Hugging Face, read from its API on 2026-11-02. Licence: CC BY 4.0.
FLEURS_REVISION = "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
FLEURS_URL = "https://huggingface.co/datasets/google/fleurs/resolve/{revision}/data/{path}"
FLEURS_SOURCE = {
    "id": "fleurs",
    "title": "FLEURS (google/fleurs)",
    "license": "CC-BY-4.0",
    "licenseURL": "https://creativecommons.org/licenses/by/4.0/",
    "url": "https://huggingface.co/datasets/google/fleurs",
    "revision": FLEURS_REVISION,
    "attribution": (
        "FLEURS: Few-shot Learning Evaluation of Universal Representations of Speech, "
        "Conneau et al. 2022 (arXiv:2205.12446), Google, licensed CC BY 4.0. "
        "Transcripts are used unchanged; audio is not redistributed."
    ),
}
# path -> (bytes, digest). Audio archives: SHA-256 (Git LFS oid). Transcripts: Git blob SHA-1.
FLEURS_FILES: dict[str, tuple[int, str]] = {
    "en_us/test.tsv": (367864, "bcd7e3e4ecb8ad2a4d9754fc6be14dd6d3364b54"),
    "en_us/dev.tsv": (213065, "4fca22b561c05159f76a7249d653c3e7677103cf"),
    "en_us/train.tsv": (1414907, "cd91b0ef2066088e86b938a9eda38d80a0e81f62"),
    "en_us/audio/test.tar.gz": (289851356, "d9c2e37b41aacd41bc283554a0a82b5476b36887049774ecb2819dcaaa55a356"),
    "hi_in/test.tsv": (473366, "57dfd6c57689c9457b9ff1f5423438f0b9cb9ad9"),
    "hi_in/audio/test.tar.gz": (249331325, "47c238b9cf7016ba596639bb3038b0c89dc6e85759f16d09c4f58c6dfa25c65f"),
    "te_in/test.tsv": (566075, "b7e43949409b11883ba89ba2dfdb18ab08f61ff2"),
    "te_in/audio/test.tar.gz": (270257144, "65d764ab4c3e9531eb61ffea4d0a78832d520f238ef0f339a7871f19c1653fd8"),
    "kn_in/test.tsv": (1071974, "c6a8f915a811152d6d4d9ead702ca8b442d94c7e"),
    "kn_in/audio/test.tar.gz": (615231116, "e9bd97241fea7373d554b37b30f13ae8dbe51549f1675334c7d824e0c4ccd51f"),
    "ta_in/test.tsv": (846022, "f1097b7f85ae798a256a0122ccc5a0c0b15d3493"),
    "ta_in/audio/test.tar.gz": (406616353, "244344ef4ca6ee0d9a0a4815686ab633ec2e8d0b70dcb7f63d53033266b99d6e"),
}
# FLEURS config -> the BCP 47 language the app and the harness use.
LANGUAGES = {"en_us": "en-US", "hi_in": "hi", "te_in": "te", "kn_in": "kn", "ta_in": "ta"}
REVIEWS = {"dataset-human", "maintainer-verified", "by-construction", "unverified"}
VARIANT_TRANSFORMS = {"noise", "clip", "pad", "speed", "repeat"}
SHA256 = re.compile(r"^[0-9a-f]{64}$")


# MARK: Checksums


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_blob_sha1(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def is_present(root: Path, path: str) -> bool:
    """A transcript that matches its pin, or an archive already extracted from a file that did."""
    if path.endswith(".tar.gz"):
        stamp = root / (path + ".extracted")
        return stamp.is_file() and stamp.read_text().strip() == FLEURS_FILES[path][1]
    return matches_pin(root / path, FLEURS_FILES[path])


def matches_pin(path: Path, pin: tuple[int, str]) -> bool:
    size, digest = pin
    if not path.is_file() or path.stat().st_size != size:
        return False
    return (sha256_of(path) if len(digest) == 64 else git_blob_sha1(path)) == digest


# MARK: fetch


def files_for(languages: list[str]) -> list[str]:
    wanted = [path for path in FLEURS_FILES if path.split("/")[0] in languages]
    # Translation references come from English, whichever languages are fetched.
    wanted += [path for path in FLEURS_FILES if path.startswith("en_us/") and path.endswith(".tsv")]
    return sorted(set(wanted))


def corpus_root(cache: Path) -> Path:
    return cache / "fleurs" / FLEURS_REVISION


def safe_extract(archive: Path, destination: Path) -> None:
    if not hasattr(tarfile, "data_filter"):
        raise SystemExit("error: this Python cannot extract archives safely (needs tarfile.data_filter)")
    with tarfile.open(archive, "r:gz") as tar:
        tar.extractall(destination, filter="data")


def fetch(cache: Path, languages: list[str], yes: bool, opener=urllib.request.urlopen) -> int:
    root = corpus_root(cache)
    needed = [path for path in files_for(languages) if not is_present(root, path)]
    total = sum(FLEURS_FILES[path][0] for path in needed)
    print(f"FLEURS {FLEURS_REVISION[:12]} → {root}")
    print(f"Licence: {FLEURS_SOURCE['license']} ({FLEURS_SOURCE['licenseURL']}). {FLEURS_SOURCE['attribution']}")
    for path in needed:
        print(f"  {path}  {FLEURS_FILES[path][0] / 1_000_000:.1f} MB")
    print(f"{len(needed)} file(s), {total / 1_000_000:.1f} MB to download.")
    if not needed:
        return 0
    if not yes:
        print("Nothing downloaded. Run again with --yes to download.")
        return 0
    for path in needed:
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_name(target.name + ".part")
        url = FLEURS_URL.format(revision=FLEURS_REVISION, path=path)
        print(f"Downloading {path} …", flush=True)
        with opener(url) as response, partial.open("wb") as out:
            for chunk in iter(lambda: response.read(1 << 20), b""):
                out.write(chunk)
        if not matches_pin(partial, FLEURS_FILES[path]):
            partial.unlink(missing_ok=True)
            print(f"error: {path} does not match its pinned checksum; deleted", file=sys.stderr)
            return 1
        if path.endswith(".tar.gz"):
            # Extract, then keep only a stamp: the recordings are what the corpus needs.
            safe_extract(partial, target.parent)
            partial.unlink()
            (root / (path + ".extracted")).write_text(FLEURS_FILES[path][1] + "\n")
        else:
            partial.replace(target)
    print("Done. Next: scripts/corpus.py build-fleurs")
    return 0


# MARK: build-fleurs


def read_tsv(path: Path) -> list[dict[str, str]]:
    """FLEURS transcripts: no header; id, file, raw text, normalized text, characters, samples, gender."""
    rows = []
    with path.open(encoding="utf-8", newline="") as handle:
        for fields in csv.reader(handle, delimiter="\t", quoting=csv.QUOTE_NONE):
            if len(fields) != 7:
                raise SystemExit(f"error: {path}: expected 7 columns, found {len(fields)}")
            rows.append({"id": fields[0], "file": fields[1], "raw": fields[2], "gender": fields[6]})
    return rows


def english_references(root: Path) -> dict[str, str]:
    references: dict[str, str] = {}
    for split in ("test", "dev", "train"):
        path = root / "en_us" / f"{split}.tsv"
        if path.is_file():
            for row in read_tsv(path):
                references.setdefault(row["id"], row["raw"])
    return references


def select(rows: list[dict[str, str]], count: int, salt: str) -> list[dict[str, str]]:
    """Deterministic and spread out: one recording of every sentence before a second of any."""

    def rank(row: dict[str, str]) -> str:
        return hashlib.sha256(f"{salt}/{row['file']}".encode()).hexdigest()

    by_sentence: dict[str, list[dict[str, str]]] = {}
    for row in sorted(rows, key=rank):
        by_sentence.setdefault(row["id"], []).append(row)
    ordered = sorted(
        ((index, rank(row), row) for group in by_sentence.values() for index, row in enumerate(group)),
        key=lambda item: (item[0], item[1]),
    )
    return [row for _, _, row in ordered[:count]]


def wav_seconds(path: Path) -> float:
    """Duration of a 16 kHz mono WAVE file, integer or float samples (FLEURS is 32-bit float)."""
    with path.open("rb") as handle:
        riff = handle.read(12)
        if len(riff) != 12 or riff[:4] != b"RIFF" or riff[8:] != b"WAVE":
            raise SystemExit(f"error: {path} is not a WAVE file")
        fmt = None
        while header := handle.read(8):
            if len(header) < 8:
                break
            name, size = header[:4], struct.unpack("<I", header[4:])[0]
            if name == b"fmt ":
                fmt = struct.unpack("<HHIIHH", handle.read(16))
                handle.seek(size - 16 + (size & 1), os.SEEK_CUR)
            elif name == b"data" and fmt is not None:
                tag, channels, rate, _, _, bits = fmt
                if tag not in WAVE_FORMATS or rate != SPEECH_SAMPLE_RATE or channels != 1:
                    raise SystemExit(f"error: {path} is not 16 kHz mono PCM or float")
                return round(size / (channels * bits // 8) / rate, 3)
            else:
                handle.seek(size + (size & 1), os.SEEK_CUR)
    raise SystemExit(f"error: {path} has no audio data")


def build_fleurs(root: Path, languages: list[str], per_language: int, variants: list[dict]) -> dict:
    english = english_references(root)
    cases = []
    for config in languages:
        tsv = root / config / "test.tsv"
        if not tsv.is_file():
            raise SystemExit(f"error: {tsv} is missing; run scripts/corpus.py fetch first")
        audio = {path.name: path for path in (root / config).rglob("*.wav")}
        for row in select(read_tsv(tsv), per_language, config):
            wav = audio.get(row["file"])
            if wav is None:
                raise SystemExit(f"error: {config}: {row['file']} is in the transcript but not in the audio")
            english_reference = None if config == "en_us" else english.get(row["id"])
            tags = ["fleurs", "read-speech", row["gender"].lower()]
            if any(character.isdigit() for character in row["raw"]):
                tags.append("numbers")
            if config != "en_us" and english_reference is None:
                tags.append("no-english-reference")
            cases.append(
                {
                    "id": f"fleurs-{config}-{Path(row['file']).stem}",
                    "source": "fleurs",
                    "language": LANGUAGES[config],
                    "audio": {
                        "path": wav.relative_to(root).as_posix(),
                        "sha256": sha256_of(wav),
                        "seconds": wav_seconds(wav),
                    },
                    "reference": row["raw"],
                    "englishReference": english_reference,
                    "category": "read",
                    "tags": tags,
                    "review": "dataset-human",
                }
            )
    return {
        "schema": SCHEMA,
        "name": "fleurs-test",
        "sources": [FLEURS_SOURCE],
        "cases": cases,
        "generated": [],
        "variants": variants,
    }


def write_json(data: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# MARK: verify


def manifest_problems(manifest: dict, root: Path | None = None) -> list[str]:
    """The same rules as CorpusManifest.problems() in Swift, plus checksums when root is given."""
    found = []
    if manifest.get("schema") != SCHEMA:
        found.append(f"schema {manifest.get('schema')} is not {SCHEMA}")
    sources = {source.get("id") for source in manifest.get("sources", [])}
    for source in manifest.get("sources", []):
        if not source.get("license") or not source.get("attribution"):
            found.append(f"source {source.get('id')} has no licence or attribution")
    seen = set()
    for item in manifest.get("cases", []) + manifest.get("generated", []) + manifest.get("variants", []):
        if item.get("id") in seen:
            found.append(f"duplicate id {item.get('id')}")
        seen.add(item.get("id"))
    for item in manifest.get("cases", []):
        name, audio = item.get("id"), item.get("audio", {})
        if item.get("source") not in sources:
            found.append(f"{name}: unknown source {item.get('source')}")
        if not SHA256.match(audio.get("sha256", "")):
            found.append(f"{name}: sha256 is not 64 hex digits")
        path = audio.get("path", "")
        if path.startswith("/") or ".." in path.split("/"):
            found.append(f"{name}: audio path must stay inside the corpus root")
        if item.get("review") not in REVIEWS:
            found.append(f"{name}: unknown review {item.get('review')}")
        if not item.get("reference") and item.get("review") != "by-construction":
            found.append(f"{name}: a recording needs a human reference")
        if root is not None and not found:
            file = root / path
            if not file.is_file():
                found.append(f"{name}: {path} is missing")
            elif sha256_of(file) != audio["sha256"]:
                found.append(f"{name}: {path} does not match its SHA-256")
    for item in manifest.get("generated", []):
        if not item.get("languages"):
            found.append(f"{item.get('id')}: no languages")
    for variant in manifest.get("variants", []):
        found += [f"{variant.get('id')}: {problem}" for problem in variant_problems(variant)]
    return found


def variant_problems(variant: dict) -> list[str]:
    """The same rules as CorpusVariant.problems() in Swift."""
    transform = variant.get("transform")
    if transform not in VARIANT_TRANSFORMS:
        return [f"unknown transform {transform}"]
    found = []
    if variant.get("sampleEvery") is not None and variant["sampleEvery"] < 1:
        found.append("sampleEvery must be at least 1")
    if transform == "noise" and (variant.get("snrDecibels") is None or variant.get("seed") is None):
        found.append("noise needs snrDecibels and seed")
    if transform == "clip" and (variant.get("gain") or 0) <= 1:
        found.append("clip needs a gain above 1")
    leading, trailing = variant.get("leading") or 0, variant.get("trailing") or 0
    if transform == "pad" and (leading < 0 or trailing < 0 or leading + trailing == 0):
        found.append("pad needs a positive leading or trailing")
    factor = variant.get("factor") or 0
    if transform == "speed" and (not 0.5 <= factor <= 2 or factor == 1):
        found.append("speed needs a factor in 0.5…2, not 1")
    if transform == "repeat" and not 2 <= (variant.get("count") or 0) <= 10:
        found.append("repeat needs a count in 2…10")
    return found


def verify(paths: list[Path], root: Path | None) -> int:
    failed = 0
    for path in paths:
        problems = manifest_problems(json.loads(path.read_text(encoding="utf-8")), root)
        for problem in problems:
            print(f"{path.name}: {problem}", file=sys.stderr)
        failed += bool(problems)
        if not problems:
            print(f"ok   {path.name}")
    return 1 if failed else 0


# MARK: Command line


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    cache = argparse.ArgumentParser(add_help=False)
    cache.add_argument("--cache", type=Path, default=Path(os.environ.get("LEMMETYPE_CORPUS_CACHE", DEFAULT_CACHE)))
    cache.add_argument("--languages", default=",".join(LANGUAGES))
    fetch_command = commands.add_parser("fetch", parents=[cache])
    fetch_command.add_argument("--yes", action="store_true", help="download (otherwise only print the plan)")
    build = commands.add_parser("build-fleurs", parents=[cache])
    build.add_argument("--per-language", type=int, default=200)
    build.add_argument("--out", type=Path, default=DEFAULT_OUT)
    build.add_argument("--variants", type=Path, default=DEFAULT_VARIANTS)
    check = commands.add_parser("verify")
    check.add_argument("manifests", nargs="+", type=Path)
    check.add_argument("--root", type=Path)
    args = parser.parse_args(argv)

    if args.command == "verify":
        return verify(args.manifests, args.root)
    languages = [language for language in args.languages.split(",") if language]
    unknown = [language for language in languages if language not in LANGUAGES]
    if unknown:
        parser.error(f"unknown FLEURS language(s): {', '.join(unknown)}")
    if args.command == "fetch":
        return fetch(args.cache, languages, args.yes)
    variants = json.loads(args.variants.read_text(encoding="utf-8"))["variants"] if args.variants.is_file() else []
    manifest = build_fleurs(corpus_root(args.cache), languages, args.per_language, variants)
    problems = manifest_problems(manifest)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    write_json(manifest, args.out)
    print(f"Wrote {len(manifest['cases'])} cases to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
