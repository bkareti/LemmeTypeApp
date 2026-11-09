#!/usr/bin/env python3
"""Record consented evaluation clips by reading a fixed script (docs/testing/cloud-speech-evaluation.md).

  scripts/record-corpus.py [--prompts FILE] [--folder DIR]

Shows one sentence at a time and records it with SoX (`rec`, 16 kHz mono) until you press
Enter. Audio and the manifest stay in ~/Library/Caches/LemmeTypeCorpus/consented/, never in
the repository. Stopping and running it again continues where you left off. The script is
the reference text, so a clip is kept only when it was read exactly. Standard library only;
run with `python3 -I`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import wave
from datetime import date
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_PROMPTS = REPO / "docs" / "testing" / "corpus" / "prompts" / "telugu-english.json"
CACHE = Path(os.environ.get("LEMMETYPE_CORPUS_CACHE", Path.home() / "Library" / "Caches" / "LemmeTypeCorpus"))
DEFAULT_FOLDER = CACHE / "consented" / "telugu-english"
SAMPLE_RATE = 16_000
MINIMUM_SECONDS = 0.5
MAXIMUM_SECONDS = 30.0  # the longest clip the cloud services accept in one request
MINIMUM_PEAK = 0.02  # of full scale; anything quieter is a muted or wrong microphone
UPLOAD_HOSTS = ["api.sarvam.ai", "api.bodhan.ai"]
SOURCE_ID = "consented-telugu-english"


def load_prompts(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["prompts"]


def audio_facts(path: Path) -> tuple[float, float]:
    """(seconds, peak as a fraction of full scale) of a 16-bit mono WAV."""
    with wave.open(str(path), "rb") as clip:
        if clip.getframerate() != SAMPLE_RATE or clip.getnchannels() != 1 or clip.getsampwidth() != 2:
            raise ValueError("not 16 kHz, mono, 16-bit")
        frames = clip.getnframes()
        data = clip.readframes(frames)
    samples = memoryview(data).cast("h") if sys.byteorder == "little" else None
    if samples is None:
        raise ValueError("big-endian hosts are not supported")
    peak = max((abs(sample) for sample in samples), default=0)
    return frames / SAMPLE_RATE, peak / 32768


def clip_problem(seconds: float, peak: float) -> str | None:
    if seconds < MINIMUM_SECONDS:
        return "too short"
    if seconds > MAXIMUM_SECONDS:
        return f"longer than {MAXIMUM_SECONDS:.0f} seconds"
    if peak < MINIMUM_PEAK:
        return "almost silent; check the microphone and its permission"
    return None


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_manifest(prompts: list[dict], folder: Path, consent_date: str) -> dict:
    cases = []
    for prompt in prompts:
        path = folder / "audio" / f"{prompt['id']}.wav"
        if not path.is_file():
            continue
        seconds, _ = audio_facts(path)
        kind = "english" if prompt["language"] == "en" else "code-mixed"
        case = {
            "id": prompt["id"], "source": SOURCE_ID, "language": prompt["language"],
            "audio": {"path": f"audio/{prompt['id']}.wav", "sha256": sha256_of(path), "seconds": round(seconds, 3)},
            "reference": prompt["reference"], "category": "dictation", "tags": ["consented", kind],
            "review": "maintainer-verified",
        }
        for field in ("referenceNative", "englishReference"):
            if prompt.get(field):
                case[field] = prompt[field]
        cases.append(case)
    return {
        "schema": 1, "name": "telugu-english-consented",
        "sources": [{
            "id": SOURCE_ID, "title": "Telugu-English script read for LemmeType evaluation",
            "license": "LicenseRef-LemmeType-consented",
            "attribution": f"Recorded with the speaker's consent on {consent_date}; not redistributed.",
            "consentDate": consent_date, "uploadHosts": UPLOAD_HOSTS,
        }],
        "cases": cases, "generated": [], "variants": [],
    }


def write_manifest(prompts: list[dict], folder: Path, consent_date: str) -> None:
    target = folder / "manifest.json"
    temporary = folder / "manifest.tmp"
    text = json.dumps(build_manifest(prompts, folder, consent_date), indent=2, ensure_ascii=False, sort_keys=True)
    temporary.write_text(text + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(target)


def consent(folder: Path) -> str:
    """The date consent was given, asking for it the first time."""
    record = folder / "consent.json"
    if record.is_file():
        return json.loads(record.read_text(encoding="utf-8"))["date"]
    print("Consent\n  These recordings are kept on this Mac and used only to evaluate LemmeType.")
    print(f"  They may be uploaded to: {', '.join(UPLOAD_HOSTS)}.")
    print(f"  To withdraw, delete {folder}.\n")
    answer = input("I am the speaker, or hold the speaker's written consent for this use (type yes): ")
    if answer.strip().lower() != "yes":
        raise SystemExit("Nothing was recorded.")
    today = date.today().isoformat()
    record.write_text(json.dumps({"date": today}) + "\n", encoding="utf-8")
    os.chmod(record, 0o600)
    return today


def record_until_enter(path: Path) -> None:
    command = ["rec", "-q", "-r", str(SAMPLE_RATE), "-c", "1", "-b", "16", str(path)]
    process = subprocess.Popen(command, stderr=subprocess.PIPE)
    try:
        input("  ● Recording. Press Enter when you finish the sentence. ")
    finally:
        process.send_signal(signal.SIGINT)
        process.wait(timeout=10)


def capture(prompt: dict, folder: Path) -> bool:
    """True when a clip was kept; False to stop for now."""
    final = folder / "audio" / f"{prompt['id']}.wav"
    draft = folder / "audio" / f"{prompt['id']}.draft.wav"
    while True:
        print(f"\n{prompt['id']}\n\n    {prompt['reference']}\n")
        if input("  Press Enter to start, or q to stop for now: ").strip().lower() == "q":
            return False
        record_until_enter(draft)
        try:
            seconds, peak = audio_facts(draft)
            problem = clip_problem(seconds, peak)
        except (OSError, EOFError, ValueError, wave.Error):
            problem = "the recording could not be read"
        if problem:
            print(f"  Try again: {problem}.")
            draft.unlink(missing_ok=True)
            continue
        while True:
            choice = input(f"  {seconds:.1f} s. k = keep (read exactly), r = retake, p = play: ").strip().lower()
            if choice == "p":
                subprocess.run(["afplay", str(draft)], check=False)
            elif choice == "r":
                draft.unlink(missing_ok=True)
                break
            elif choice == "k":
                os.chmod(draft, 0o600)
                draft.replace(final)
                return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--prompts", type=Path, default=DEFAULT_PROMPTS)
    parser.add_argument("--folder", type=Path, default=DEFAULT_FOLDER)
    args = parser.parse_args(argv)
    prompts = load_prompts(args.prompts)
    (args.folder / "audio").mkdir(parents=True, exist_ok=True, mode=0o700)
    consent_date = consent(args.folder)
    remaining = [prompt for prompt in prompts if not (args.folder / "audio" / f"{prompt['id']}.wav").is_file()]
    print(f"{len(prompts) - len(remaining)} of {len(prompts)} recorded. Use a quiet room and your usual voice.")
    for prompt in remaining:
        if not capture(prompt, args.folder):
            break
        write_manifest(prompts, args.folder, consent_date)
    write_manifest(prompts, args.folder, consent_date)
    done = sum((args.folder / "audio" / f"{prompt['id']}.wav").is_file() for prompt in prompts)
    print(f"\n{done} of {len(prompts)} recorded. Manifest: {args.folder / 'manifest.json'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
