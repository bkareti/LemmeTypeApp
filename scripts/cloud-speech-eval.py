#!/usr/bin/env python3
"""Cloud speech evaluation: score hosted speech-to-text services on the committed corpus,
the same way the Swift harness scores the local engines (docs/testing/cloud-speech-evaluation.md).

  scripts/cloud-speech-eval.py run --provider bodhan|sarvam [--task transcribe|translate]
                               [--output native|codemix] [--languages hi,te] [--limit N]
                               [--manifest FILE] [--root DIR] [--workers 1]
                               [--reference-field reference|referenceNative] [--yes]
      Without --yes it only prints what would be uploaded, where, and the estimated cost.
      With --yes it uploads each recording once (answers are cached, so a rerun costs
      nothing) and writes an EvaluationReport (schema 2) to build/evaluation/cloud/.

  scripts/cloud-speech-eval.py compare REPORT_OR_FOLDER... [--markdown FILE]
      Pooled word and character error rates per language for every report, on the cases
      all of them answered (original recordings only), so the comparison is like for like.
      A request that failed is counted in its own column and never scored as a blank.

This is an evaluation tool, never part of the app: the app stays network-silent. It
uploads corpus audio only (public FLEURS recordings, or consented recordings whose
manifest says so). API keys come from the environment (BODHAN_API_KEY, SARVAM_API_KEY) or
from ~/.config/lemmetype/cloud-eval.env (KEY=value lines, readable by you only); keys are
never printed or written anywhere else. Transcripts are cached outside the repository in
~/Library/Caches/LemmeTypeCorpus/cloud/; reports hold metrics and case ids only.
Standard library only; run with `python3 -I`.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import platform
import re
import stat
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPO / "docs" / "testing" / "corpus" / "fleurs.json"
FLEURS_REVISION = "70bb2e84b976b7e960aa89f1c648e09c59f894dd"
CACHE = Path(os.environ.get("LEMMETYPE_CORPUS_CACHE", Path.home() / "Library" / "Caches" / "LemmeTypeCorpus"))
DEFAULT_ROOT = CACHE / "fleurs" / FLEURS_REVISION
ANSWERS = CACHE / "cloud"
DEFAULT_OUT = REPO / "build" / "evaluation" / "cloud"
KEY_FILE = Path.home() / ".config" / "lemmetype" / "cloud-eval.env"
REPORT_SCHEMA = 2
USER_AGENT = "LemmeType-evaluation/1"
TIMEOUT_SECONDS = 60
ATTEMPTS = 4


# MARK: Providers


class ProviderError(Exception):
    """A request that failed; `code` is a short identifier safe to put in a report."""

    def __init__(self, code: str, retryable: bool, detail: str = "") -> None:
        super().__init__(f"{code}: {detail}" if detail else code)
        self.code = code
        self.retryable = retryable


class Provider:
    name = ""
    model = ""
    host = ""
    key_name = ""
    rupees_per_minute = 0.0  # list price, for the estimate only
    price_note = ""
    tasks: tuple[str, ...] = ("transcribe",)
    outputs: tuple[str, ...] = ("native",)
    languages: dict[str, str] = {}

    def label(self, output: str) -> str:
        base = f"{self.name}-{self.model}".replace(":", "-").replace(".", "-")
        return base if output == "native" else f"{base}-{output}"

    def request(self, key: str, audio: bytes, filename: str, language: str, task: str, output: str) -> tuple[str, dict]:
        raise NotImplementedError

    def parse(self, body: dict) -> tuple[str, str | None]:
        raise NotImplementedError


class Bodhan(Provider):
    """Bodhan Indic-Transcribe (console.bodhan.ai/api-docs): OpenAI-shaped transcription."""

    name = "bodhan"
    model = "indic-transcribe"
    host = "api.bodhan.ai"
    key_name = "BODHAN_API_KEY"
    rupees_per_minute = 0.10
    price_note = "₹0.10 per audio minute, billed per second (launch price, Sept 2026)"
    languages = {"en-US": "en", "en": "en", "hi": "hi", "te": "te", "ta": "ta", "kn": "kn", "ml": "ml"}

    def request(self, key, audio, filename, language, task, output):
        fields = {"model": self.model, "language": self.languages[language]}
        body, content_type = multipart(fields, audio, filename)
        headers = {"Authorization": f"Bearer {key}", "Content-Type": content_type}
        return f"https://{self.host}/v1/audio/transcriptions", {"headers": headers, "body": body}

    def parse(self, body):
        return body.get("text") or "", None


class Sarvam(Provider):
    """Sarvam Saaras (docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe)."""

    name = "sarvam"
    model = "saaras:v4"
    host = "api.sarvam.ai"
    key_name = "SARVAM_API_KEY"
    rupees_per_minute = 0.49
    price_note = "₹0.49 per audio minute, billed per second (pay as you go, read 2026-11-09)"
    tasks = ("transcribe", "translate")
    outputs = ("native", "codemix")
    languages = {"en-US": "en-IN", "en": "en-IN", "hi": "hi-IN", "te": "te-IN", "ta": "ta-IN", "kn": "kn-IN",
                 "ml": "ml-IN"}

    def request(self, key, audio, filename, language, task, output):
        mode = "translate" if task == "translate" else ("codemix" if output == "codemix" else "transcribe")
        fields = {"model": self.model, "mode": mode, "language_code": self.languages[language]}
        body, content_type = multipart(fields, audio, filename)
        headers = {"api-subscription-key": key, "Content-Type": content_type}
        return f"https://{self.host}/speech-to-text", {"headers": headers, "body": body}

    def parse(self, body):
        return body.get("transcript") or "", body.get("language_code")


PROVIDERS: dict[str, Provider] = {provider.name: provider for provider in (Bodhan(), Sarvam())}


def multipart(fields: dict[str, str], audio: bytes, filename: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: audio/wav\r\n\r\n".encode() + audio + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def send(provider: Provider, key: str, audio: bytes, filename: str, language: str, task: str, output: str,
         opener=urllib.request.urlopen, sleep=time.sleep) -> tuple[str, str | None, float]:
    """(text, detected language, seconds) for one recording, retrying rate limits and server errors."""
    for attempt in range(ATTEMPTS):
        url, parts = provider.request(key, audio, filename, language, task, output)
        request = urllib.request.Request(url, data=parts["body"], method="POST",
                                         headers={**parts["headers"], "User-Agent": USER_AGENT})
        started = time.monotonic()
        try:
            with opener(request, timeout=TIMEOUT_SECONDS) as response:
                body = json.loads(response.read().decode("utf-8"))
            text, detected = provider.parse(body)
            return text, detected, time.monotonic() - started
        except urllib.error.HTTPError as error:
            retryable = error.code == 429 or error.code >= 500
            failure = ProviderError(f"http-{error.code}", retryable, error_code(error))
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            failure = ProviderError("network", True, type(error).__name__)
        except (ValueError, UnicodeDecodeError):
            failure = ProviderError("bad-response", False)
        if not failure.retryable or attempt == ATTEMPTS - 1:
            raise failure
        sleep(2 ** attempt)
    raise AssertionError("unreachable")


def error_code(error: urllib.error.HTTPError) -> str:
    """The provider's symbolic error code, never the message (it can echo request details)."""
    try:
        body = json.loads(error.read().decode("utf-8"))
        code = (body.get("error") or {}).get("code") if isinstance(body, dict) else None
        return code if isinstance(code, str) and re.fullmatch(r"[a-z0-9_-]{1,64}", code) else ""
    except (ValueError, UnicodeDecodeError, AttributeError):
        return ""
    finally:
        error.close()


# MARK: Keys


def api_key(name: str, environ=os.environ, key_file: Path = KEY_FILE) -> str | None:
    value = environ.get(name, "").strip()
    if value and value != "...":
        return value
    if not key_file.is_file():
        return None
    if key_file.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        raise SystemExit(f"error: {key_file} is readable by other users; run: chmod 600 {key_file}")
    for line in key_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("export "):
            line = line[len("export "):].strip()
        if line.startswith(name + "="):
            value = line.split("=", 1)[1].strip().strip("'\"")
            return value if value and value != "..." else None
    return None


# MARK: Scoring (the same rules as TestSupport in Swift: TranscriptNormalizer, EditAlignment,
# NumberNormalizer, TranscriptScore, CharacterNGramStatistics)

IGNORED = {"​", "‌", "‍", "﻿"}
WORD_CATEGORIES = {"Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No"}


def words(text: str) -> list[str]:
    out = []
    for char in unicodedata.normalize("NFC", text).lower():
        if char in IGNORED:
            continue
        if char in "’‘":
            out.append("'")
        elif char == "'" or unicodedata.category(char) in WORD_CATEGORIES:
            out.append(char)
        else:
            out.append(" ")
    return "".join(out).split()


def normalize(text: str) -> str:
    return " ".join(words(text))


def align(reference: list, hypothesis: list) -> dict:
    """Levenshtein split by kind; ties resolve like EditAlignment.align (substitute, delete, insert)."""
    previous = [(0, 0, column) for column in range(len(hypothesis) + 1)]
    for row, expected in enumerate(reference):
        current = [(0, row + 1, 0)]
        for column, actual in enumerate(hypothesis):
            s, d, i = previous[column]
            best = (s + (expected != actual), d, i)
            s, d, i = previous[column + 1]
            delete = (s, d + 1, i)
            s, d, i = current[column]
            insert = (s, d, i + 1)
            if sum(delete) < sum(best):
                best = delete
            if sum(insert) < sum(best):
                best = insert
            current.append(best)
        previous = current
    s, d, i = previous[len(hypothesis)]
    return {"deletions": d, "insertions": i, "referenceLength": len(reference), "substitutions": s}


def error_rate(alignment: dict) -> float:
    edits = alignment["substitutions"] + alignment["deletions"] + alignment["insertions"]
    if alignment["referenceLength"] == 0:
        return 0.0 if edits == 0 else 1.0
    return edits / alignment["referenceLength"]


UNITS = {"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
         "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
         "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
        "ninety": 90}
SCALES = {"thousand": 1_000, "million": 1_000_000, "billion": 1_000_000_000}


def is_number_word(word: str) -> bool:
    lower = word.lower()
    return lower in UNITS or lower in TENS or lower in SCALES or lower == "hundred"


def fold_digits(text: str) -> str:
    out = []
    for char in text:
        value = unicodedata.decimal(char, None)
        out.append(str(value) if value is not None and 0 <= value <= 9 else char)
    return "".join(out)


def normalize_numbers(text: str) -> str:
    folded = re.sub(r"(?<=\d),(?=\d{3}(?!\d))", "", fold_digits(text))
    return spoken_numbers_to_digits(folded)


def spoken_numbers_to_digits(text: str) -> str:
    spans = [match.span() for match in re.finditer(r"[A-Za-z]+", text)]
    output, cursor, index = [], 0, 0
    while index < len(spans):
        start, run, end = index, [], index
        while end < len(spans):
            word = text[spans[end][0]:spans[end][1]]
            gap = "" if end == start else text[spans[end - 1][1]:spans[end][0]]
            if not (end == start or gap in (" ", "-")):
                break
            if is_number_word(word):
                run.append(word.lower())
                end += 1
            elif (word.lower() == "and" and run and end + 1 < len(spans)
                  and is_number_word(text[spans[end + 1][0]:spans[end + 1][1]])
                  and (run[-1] == "hundred" or run[-1] in SCALES)):
                end += 1
            else:
                break
        value = number_value(run) if run else None
        if value is None:
            index = max(index + 1, end)
            continue
        output.append(text[cursor:spans[start][0]])
        output.append(value)
        cursor = spans[end - 1][1]
        index = end
    output.append(text[cursor:])
    return "".join(output)


def number_value(run: list[str]) -> str | None:
    year = year_style(run)
    if year is not None:
        return year
    if run == ["zero"]:
        return "0"
    total, group, last = 0, 0, "start"
    for word in run:
        if word in UNITS and UNITS[word] > 0:
            unit = UNITS[word]
            fits = group % 100 == 0 if last in ("start", "hundred", "scale") else (unit < 10 if last == "ten" else False)
            if not fits:
                return None
            group, last = group + unit, "unit"
        elif word in TENS:
            if last not in ("start", "hundred", "scale") or group % 100 != 0:
                return None
            group, last = group + TENS[word], "ten"
        elif word == "hundred":
            if last not in ("unit", "ten") or not 1 <= group <= 99:
                return None
            group, last = group * 100, "hundred"
        elif word in SCALES:
            if group <= 0 or last == "scale":
                return None
            total, group, last = total + group * SCALES[word], 0, "scale"
        else:
            return None
    return str(total + group)


def year_style(run: list[str]) -> str | None:
    if not 2 <= len(run) <= 4 or "hundred" in run or any(word in SCALES for word in run):
        return None
    for split in range(1, len(run)):
        first, second = small_value(run[:split]), small_value(run[split:])
        if first is not None and second is not None and 10 <= first <= 99 and 10 <= second <= 99 and first != 10:
            return str(first * 100 + second)
    return None


def small_value(parts: list[str]) -> int | None:
    if len(parts) == 1:
        return UNITS.get(parts[0], TENS.get(parts[0]))
    if len(parts) == 2 and parts[0] in TENS and 1 <= UNITS.get(parts[1], 0) <= 9:
        return TENS[parts[0]] + UNITS[parts[1]]
    return None


def longest_repeat(tokens: list[str]) -> int:
    longest = 1 if tokens else 0
    for length in range(1, 5):
        if length * 2 > len(tokens):
            break
        for start in range(0, len(tokens) - length * 2 + 1):
            copies = 1
            while (start + length * (copies + 1) <= len(tokens)
                   and tokens[start:start + length] == tokens[start + length * copies:start + length * (copies + 1)]):
                copies += 1
            longest = max(longest, copies)
    return longest


def score(reference: str, hypothesis: str) -> dict:
    expected, actual = words(reference), words(hypothesis)
    repeats = longest_repeat(actual)
    return {
        "characters": align(list(normalize(reference)), list(normalize(hypothesis))),
        "numberNormalizedWords": align(words(normalize_numbers(reference)), words(normalize_numbers(hypothesis))),
        "repetitionLoop": repeats >= 3 and repeats > longest_repeat(expected),
        "textWithoutSpeech": not expected and bool(actual),
        "words": align(expected, actual),
    }


def character_ngrams(reference: str, hypothesis: str) -> dict:
    def grams(text: str, order: int) -> dict[str, int]:
        scalars = [char for char in unicodedata.normalize("NFC", text) if not char.isspace()]
        counts: dict[str, int] = {}
        for start in range(0, len(scalars) - order + 1):
            gram = "".join(scalars[start:start + order])
            counts[gram] = counts.get(gram, 0) + 1
        return counts

    statistics = {"hypothesis": [], "matches": [], "reference": []}
    for order in range(1, 7):
        wanted, got = grams(reference, order), grams(hypothesis, order)
        statistics["reference"].append(sum(wanted.values()))
        statistics["hypothesis"].append(sum(got.values()))
        statistics["matches"].append(sum(min(count, wanted.get(gram, 0)) for gram, count in got.items()))
    return statistics


def chrf(statistics: dict) -> float:
    total, orders = 0.0, 0
    for hypothesis, reference, matches in zip(statistics["hypothesis"], statistics["reference"], statistics["matches"]):
        if hypothesis > 0 and reference > 0:
            precision, recall = matches / hypothesis, matches / reference
            denominator = 4 * precision + recall
            total += 5 * precision * recall / denominator if denominator > 0 else 0.0
            orders += 1
    if orders == 0:
        return 100.0 if not any(statistics["reference"]) and not any(statistics["hypothesis"]) else 0.0
    return 100 * total / orders


def english_kept(reference: str, hypothesis: str) -> dict:
    """How many of the reference's English words came back in English letters, in any order."""
    def latin(tokens: list[str]) -> dict[str, int]:
        counts: dict[str, int] = {}
        for token in tokens:
            if token.isascii() and any(char.isalpha() for char in token):
                counts[token] = counts.get(token, 0) + 1
        return counts

    wanted, got = latin(words(reference)), latin(words(hypothesis))
    return {"englishWords": sum(wanted.values()), "kept": sum(min(count, got.get(word, 0)) for word, count in wanted.items())}


# MARK: run


def load_cases(manifest: Path, languages: list[str] | None, limit: int | None) -> list[dict]:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    cases = [case for case in data["cases"] if case.get("audio")]
    if languages:
        cases = [case for case in cases if case["language"].split("-")[0] in languages]
    if limit:
        per_language: dict[str, int] = {}
        kept = []
        for case in cases:
            count = per_language.get(case["language"], 0)
            if count < limit:
                kept.append(case)
                per_language[case["language"]] = count + 1
        cases = kept
    return cases


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def answer_path(label: str, task: str, case_id: str) -> Path:
    return ANSWERS / f"{label}-{task}" / f"{case_id}.json"


def run(args: argparse.Namespace, opener=urllib.request.urlopen) -> int:
    provider = PROVIDERS[args.provider]
    if args.task not in provider.tasks:
        raise SystemExit(f"error: {provider.name} has no {args.task} task")
    if args.output not in provider.outputs:
        raise SystemExit(f"error: {provider.name} has no {args.output} output")
    languages = [code.strip() for code in args.languages.split(",")] if args.languages else None
    cases = load_cases(args.manifest, languages, args.limit)
    if args.task == "translate":
        cases = [case for case in cases if case.get("englishReference") and case["language"].split("-")[0] != "en"]
    unsupported = sorted({case["language"] for case in cases if case["language"] not in provider.languages})
    if unsupported:
        raise SystemExit(f"error: {provider.name} has no language mapping for {', '.join(unsupported)}")
    if not cases:
        raise SystemExit("error: no cases match")
    if any(not case.get(args.reference_field) for case in cases):
        raise SystemExit(f"error: some cases have no {args.reference_field}")
    label = provider.label(args.output)
    pending = [case for case in cases if not answer_path(label, args.task, case["id"]).is_file()]
    minutes = sum(case["audio"]["seconds"] for case in pending) / 60
    print(f"{label} · {args.task}: {len(cases)} recordings, {len(pending)} not answered yet "
          f"({minutes:.1f} min of audio to upload to {provider.host}).")
    print(f"Estimated cost: ₹{minutes * provider.rupees_per_minute:.2f} at {provider.price_note}.")
    print(f"Audio comes from {args.manifest.relative_to(REPO) if args.manifest.is_relative_to(REPO) else args.manifest}; "
          f"answers are cached in {ANSWERS / (label + '-' + args.task)}.")
    if pending and not args.yes:
        print("Nothing was uploaded. Add --yes to upload.")
        return 0
    key = api_key(provider.key_name) if pending else ""
    if pending and not key:
        raise SystemExit(f"error: no {provider.key_name}: export it, or add {provider.key_name}=... to {KEY_FILE} "
                         f"(chmod 600)")

    failures: dict[str, str] = {}
    lock = threading.Lock()
    done = [0]

    def answer(case: dict) -> None:
        path = args.root / case["audio"]["path"]
        if not path.is_file():
            raise SystemExit(f"error: {path} is missing; fetch the corpus first (docs/testing/corpus/README.md)")
        if sha256_of(path) != case["audio"]["sha256"]:
            raise SystemExit(f"error: {path} does not match its manifest checksum")
        try:
            text, detected, seconds = send(provider, key, path.read_bytes(), path.name, case["language"], args.task,
                                           args.output, opener=opener)
        except ProviderError as error:
            with lock:
                failures[case["id"]] = error.code
            return
        target = answer_path(label, args.task, case["id"])
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        temporary = target.with_suffix(".tmp")
        temporary.write_text(json.dumps({"text": text, "language": detected, "seconds": seconds}, ensure_ascii=False),
                             encoding="utf-8")
        os.chmod(temporary, 0o600)
        temporary.replace(target)
        with lock:
            done[0] += 1
            if done[0] % 25 == 0:
                print(f"  {done[0]}/{len(pending)} answered")

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        list(pool.map(answer, pending))
    if failures:
        counts: dict[str, int] = {}
        for code in failures.values():
            counts[code] = counts.get(code, 0) + 1
        print("Failed requests (not cached; a rerun retries them): "
              + ", ".join(f"{code} ×{count}" for code, count in sorted(counts.items())))
    report = build_report(provider, label, args.task, args.manifest, cases, failures, args.reference_field)
    args.out.mkdir(parents=True, exist_ok=True)
    destination = args.out / f"{report['label']}-{args.task}-exact.json"
    destination.write_text(json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {destination.relative_to(REPO) if destination.is_relative_to(REPO) else destination}")
    return 1 if failures and not args.allow_failures else 0


def build_report(provider: Provider, label: str, task: str, manifest: Path, cases: list[dict],
                 failures: dict[str, str], reference_field: str = "reference") -> dict:
    runs = []
    for case in cases:
        reference = case["englishReference"] if task == "translate" else case[reference_field]
        path = answer_path(label, task, case["id"])
        if path.is_file():
            answer = json.loads(path.read_text(encoding="utf-8"))
            text, seconds, outcome = answer["text"], answer["seconds"], "delivered"
        else:
            text, seconds, outcome = "", 0.0, failures.get(case["id"], "not-answered")
        result = {
            "audioSeconds": case["audio"]["seconds"],
            "category": case.get("category", "read"),
            "id": case["id"],
            "inferenceSeconds": seconds,
            "language": case["language"],
            "mode": "exact",
            "outcome": outcome,
            "producedText": bool(words(text)),
            "score": score(reference, text),
            "stopToDeliverySeconds": seconds,
            "task": task,
            "writingMode": "exact",
        }
        if task == "translate":
            # chrF only. The meaning checks (PreservationChecker) are Swift-only, so they are
            # left out rather than reported as passing; compare shows this chrF.
            result["cloudTranslation"] = {"characterNGrams": character_ngrams(reference, text)}
        if task == "transcribe" and "code-mixed" in case.get("tags", []) and reference_field == "reference":
            result["cloudCodeMix"] = english_kept(reference, text)
        runs.append({"baseID": case["id"], "id": case["id"], "result": result, "review": case.get("review", "unverified"),
                     "source": case.get("source"), "tags": case.get("tags", [])})
    manifest_bytes = manifest.read_bytes()
    return {
        "corpora": [{"name": json.loads(manifest_bytes)["name"], "runs": len(runs),
                     "sha256": hashlib.sha256(manifest_bytes).hexdigest()}],
        "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "engine": provider.name,
        "hardwareModel": f"cloud:{provider.host}",
        "label": label if reference_field == "reference" else f"{label}-native-reference",
        "mode": "exact",
        "operatingSystem": f"client {platform.system()} {platform.release()}",
        "peakMemoryIncreaseMB": 0,
        "physicalMemoryGB": 0,
        "runs": runs,
        "schema": REPORT_SCHEMA,
        "skipped": {},
        "style": "none",
        "task": task,
        "warmUpSeconds": 0,
        "writingMode": "exact",
    }


# MARK: compare


def load_reports(paths: list[Path]) -> list[dict]:
    reports = []
    for path in paths:
        for file in sorted(path.glob("*.json")) if path.is_dir() else [path]:
            data = json.loads(file.read_text(encoding="utf-8"))
            if isinstance(data, dict) and {"schema", "label", "task", "runs"} <= data.keys():
                reports.append(data)
    return reports


def request_failed(run: dict) -> bool:
    outcome = run["result"]["outcome"]
    return outcome.startswith("http-") or outcome in ("network", "bad-response", "not-answered")


def speech_runs(report: dict) -> dict[str, dict]:
    return {run["id"]: run for run in report["runs"]
            if not run.get("variantID") and run["review"] != "unverified"
            and run["result"]["score"]["words"]["referenceLength"] > 0}


def originals(report: dict) -> dict[str, dict]:
    return {case_id: run for case_id, run in speech_runs(report).items() if not request_failed(run)}


def pooled(runs: list[dict], field: str) -> float | None:
    edits = reference = 0
    for run in runs:
        alignment = run["result"]["score"][field]
        edits += alignment["substitutions"] + alignment["deletions"] + alignment["insertions"]
        reference += alignment["referenceLength"]
    return edits / reference if reference else None


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def compare_rows(reports: list[dict]) -> list[dict]:
    by_task: dict[str, list[dict]] = {}
    for report in reports:
        by_task.setdefault(report["task"], []).append(report)
    rows = []
    for task, group in sorted(by_task.items()):
        shared = set.intersection(*(set(originals(report)) for report in group))
        for report in group:
            runs = [run for case_id, run in originals(report).items() if case_id in shared]
            for language in sorted({run["result"]["language"].split("-")[0] for run in runs}):
                selected = [run for run in runs if run["result"]["language"].split("-")[0] == language]
                latencies = [run["result"]["stopToDeliverySeconds"] for run in selected if run["result"]["producedText"]]
                row = {
                    "task": task, "label": report["label"], "mode": report.get("mode", ""), "language": language,
                    "runs": len(selected), "wer": pooled(selected, "words"), "cer": pooled(selected, "characters"),
                    "werNumbers": pooled(selected, "numberNormalizedWords"),
                    "noText": sum(not run["result"]["producedText"] for run in selected) / len(selected),
                    "p50": percentile(latencies, 0.5), "p95": percentile(latencies, 0.95), "chrF": None,
                    "failed": sum(request_failed(run) and run["result"]["language"].split("-")[0] == language
                                  for run in speech_runs(report).values()),
                    "englishKept": None,
                }
                mixes = [run["result"]["cloudCodeMix"] for run in selected if run["result"].get("cloudCodeMix")]
                if sum(mix["englishWords"] for mix in mixes):
                    row["englishKept"] = sum(mix["kept"] for mix in mixes) / sum(mix["englishWords"] for mix in mixes)
                grams = [run["result"].get("cloudTranslation", run["result"].get("translation") or {}).get("characterNGrams")
                         for run in selected]
                if grams and all(grams):
                    total = {name: [sum(values) for values in zip(*(gram[name] for gram in grams))]
                             for name in ("hypothesis", "matches", "reference")}
                    row["chrF"] = chrf(total)
                rows.append(row)
    return rows


def percent(value: float | None) -> str:
    return "–" if value is None else f"{100 * value:.1f}%"


def seconds(value: float | None) -> str:
    return "–" if value is None else f"{value:.2f} s"


def compare(args: argparse.Namespace) -> int:
    reports = load_reports(args.reports)
    if not reports:
        raise SystemExit("error: no reports found")
    rows = compare_rows(reports)
    lines = ["| Task | Engine | Language | Runs | CER | WER | WER (numbers as digits) | chrF | English kept | No text | Failed | p50 | p95 |",
             "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for row in sorted(rows, key=lambda row: (row["task"], row["language"], row["cer"] if row["cer"] is not None else 9)):
        chrf_text = "–" if row["chrF"] is None else f"{row['chrF']:.1f}"
        lines.append(f"| {row['task']} | {row['label']} ({row['mode']}) | {row['language']} | {row['runs']} | "
                     f"{percent(row['cer'])} | {percent(row['wer'])} | {percent(row['werNumbers'])} | {chrf_text} | "
                     f"{percent(row['englishKept'])} | {percent(row['noText'])} | {row['failed']} | "
                     f"{seconds(row['p50'])} | {seconds(row['p95'])} |")
    table = "\n".join(lines)
    print(table)
    if args.markdown:
        args.markdown.parent.mkdir(parents=True, exist_ok=True)
        args.markdown.write_text(table + "\n", encoding="utf-8")
    return 0


# MARK: main


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("--provider", choices=sorted(PROVIDERS), required=True)
    run_parser.add_argument("--task", choices=("transcribe", "translate"), default="transcribe")
    run_parser.add_argument("--output", choices=("native", "codemix"), default="native")
    run_parser.add_argument("--languages")
    run_parser.add_argument("--limit", type=int, help="at most N recordings per language")
    run_parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    run_parser.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    run_parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    run_parser.add_argument("--workers", type=int, default=1, help="parallel requests; more than 1 can hit rate limits")
    run_parser.add_argument("--reference-field", choices=("reference", "referenceNative"), default="reference",
                            help="referenceNative scores against English words written in the native script")
    run_parser.add_argument("--allow-failures", action="store_true")
    run_parser.add_argument("--yes", action="store_true", help="upload; without it nothing leaves this Mac")
    compare_parser = commands.add_parser("compare")
    compare_parser.add_argument("reports", type=Path, nargs="+")
    compare_parser.add_argument("--markdown", type=Path)
    args = parser.parse_args(argv)
    return run(args) if args.command == "run" else compare(args)


if __name__ == "__main__":
    sys.exit(main())
