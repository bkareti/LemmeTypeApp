#!/usr/bin/env python3
"""Writes the hand-made evaluation report fixtures shared by the Swift EvaluationReportTests and
scripts/tests/test-evaluation-report.py. Every number here is test data, not a measurement.

  python3 -I scripts/tests/fixtures/make-evaluation-fixtures.py
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
# "the cat" against "the hat" (TranslationAndStyleScoreTests): chrF = 100 × (5/6 + 3/5 + 1/4) / 6.
CAT_HAT = {"hypothesis": [6, 5, 4, 3, 2, 1], "reference": [6, 5, 4, 3, 2, 1], "matches": [5, 3, 1, 0, 0, 0]}
IDENTICAL = {"hypothesis": [20, 19, 18, 17, 16, 15], "reference": [20, 19, 18, 17, 16, 15],
             "matches": [20, 19, 18, 17, 16, 15]}
EMPTY_HYPOTHESIS = {"hypothesis": [0] * 6, "reference": [10, 9, 8, 7, 6, 5], "matches": [0] * 6}


def alignment(reference: int, substitutions: int = 0, deletions: int = 0, insertions: int = 0) -> dict:
    return {"referenceLength": reference, "substitutions": substitutions, "deletions": deletions,
            "insertions": insertions}


def run(id, base, language, task="transcribe", mode="clean", variant=None, tags=(), review="dataset-human",
        words=(8, 1, 0, 0), normalized=None, characters=(40, 2, 0, 0), produced=True, outcome="delivered",
        silent_text=False, loop=False, audio=6.0, inference=1.5, latency=1.8, category="read", translation=None,
        style=None):
    return {
        "id": id, "baseID": base, "variantID": variant, "review": review, "tags": list(tags),
        "source": None if review == "by-construction" else "fleurs",
        "result": {
            "id": id, "category": category, "language": language, "task": task, "mode": mode,
            "writingMode": "exact" if mode == "exact" else "clean", "outcome": outcome, "producedText": produced,
            "audioSeconds": audio, "inferenceSeconds": inference, "stopToDeliverySeconds": latency,
            "score": {"words": alignment(*words), "numberNormalizedWords": alignment(*(normalized or words)),
                      "characters": alignment(*characters), "textWithoutSpeech": silent_text,
                      "repetitionLoop": loop},
            "translation": translation, "style": style,
        },
    }


def report(label, task, mode, style, runs, corpora):
    return {"schema": 2, "label": label, "engine": "fake", "task": task, "mode": mode,
            "writingMode": "exact" if mode == "exact" else "clean", "style": style,
            "date": "2026-11-02T12:00:00Z", "operatingSystem": "Fixture OS", "hardwareModel": "Fixture1,1",
            "physicalMemoryGB": 16, "warmUpSeconds": 0.75, "peakMemoryIncreaseMB": 120.5, "corpora": corpora,
            "skipped": {"already-english": 0}, "runs": runs}


def transcription() -> dict:
    fleurs = ["fleurs", "read-speech"]
    runs = [
        run("fleurs-hi_in-1", "fleurs-hi_in-1", "hi", tags=fleurs + ["female"]),
        run("fleurs-hi_in-2", "fleurs-hi_in-2", "hi", tags=fleurs + ["male", "numbers"], words=(8, 3, 0, 0),
            normalized=(8, 1, 0, 0), characters=(40, 6, 0, 0)),
        run("fleurs-te_in-1", "fleurs-te_in-1", "te", tags=fleurs + ["male"], words=(6, 2, 0, 0),
            characters=(50, 4, 0, 0)),
        run("fleurs-te_in-2", "fleurs-te_in-2", "te", tags=fleurs + ["male"], words=(5, 0, 5, 0),
            characters=(30, 0, 30, 0), produced=False, outcome="recognition.no-speech", inference=1.0, latency=1.1),
        run("fleurs-te_in-3", "fleurs-te_in-3", "te", tags=fleurs + ["female"], words=(4, 0, 0, 8),
            characters=(25, 2, 0, 30), loop=True, latency=3.9),
        run("fleurs-hi_in-1~noise-snr10", "fleurs-hi_in-1", "hi", variant="noise-snr10",
            tags=fleurs + ["female", "variant:noise"], words=(8, 2, 0, 0), characters=(40, 5, 0, 0)),
        run("silence-2s@hi", "silence-2s", "hi", tags=["generated:silence"], review="by-construction",
            words=(0,), characters=(0,), produced=False, outcome="recognition.silent-audio", audio=2.0,
            inference=0.0, latency=0.05, category="no-speech"),
        run("noise-loud@te", "noise-loud", "te", tags=["generated:noise"], review="by-construction",
            words=(0, 0, 0, 3), characters=(0, 0, 0, 14), silent_text=True, audio=3.0, inference=0.8,
            latency=0.9, category="no-speech"),
        run("model-guess-1", "model-guess-1", "hi", tags=["fleurs"], review="unverified", words=(8, 8, 0, 0),
            characters=(40, 40, 0, 0)),
    ]
    return report("fixture", "transcribe", "clean", "none", runs,
                  [{"name": "fleurs-test", "runs": 7, "sha256": "a" * 64},
                   {"name": "edge-cases", "runs": 2, "sha256": "b" * 64}])


def translation() -> dict:
    task = "translate-to-english"

    def scored(statistics, violations=()):
        return {"characterNGrams": statistics, "violations": list(violations)}

    runs = [
        run("fleurs-hi_in-1", "fleurs-hi_in-1", "hi", task=task, outcome="review.translation",
            translation=scored(CAT_HAT)),
        run("fleurs-hi_in-2", "fleurs-hi_in-2", "hi", task=task, outcome="review.translation",
            translation=scored(IDENTICAL, ["negation-changed"])),
        run("fleurs-te_in-1", "fleurs-te_in-1", "te", task=task, outcome="review.translation",
            translation=scored(IDENTICAL, ["number-changed", "name-changed"])),
        run("fleurs-te_in-2", "fleurs-te_in-2", "te", task=task, words=(5, 0, 5, 0), produced=False,
            outcome="recognition.no-speech", translation=scored(EMPTY_HYPOTHESIS)),
        run("fleurs-te_in-3", "fleurs-te_in-3", "te", task=task, outcome="review.translation",
            translation=scored(IDENTICAL, ["name-changed"])),
        run("fleurs-hi_in-1~noise-snr10", "fleurs-hi_in-1", "hi", task=task, variant="noise-snr10",
            outcome="review.translation", translation=scored(IDENTICAL)),
        run("silence-2s@hi", "silence-2s", "hi", task=task, review="by-construction", words=(0,), characters=(0,),
            produced=False, outcome="recognition.silent-audio", category="no-speech",
            translation=scored({"hypothesis": [0] * 6, "reference": [0] * 6, "matches": [0] * 6})),
    ]
    return report("fixture", task, "clean", "none", runs, [{"name": "fleurs-test", "runs": 6, "sha256": "a" * 64}])


def style() -> dict:
    mode, identifier = "style-neutral-bullet-list-concise", "neutral-bullet-list-concise"

    def styled(applied=True, notice=None, violations=(), format_followed=True, length_followed=True, before=12,
               after=8):
        return {"style": identifier, "applied": applied, "notice": notice, "violations": list(violations),
                "format": ("followed" if format_followed else "not-followed") if applied else "not-checked",
                "length": ("followed" if length_followed else "not-followed") if applied else "not-checked",
                "originalWords": before,
                "rewrittenWords": after if applied else before}

    runs = [
        run("fleurs-hi_in-1", "fleurs-hi_in-1", "hi", mode=mode, outcome="review", style=styled()),
        run("fleurs-hi_in-2", "fleurs-hi_in-2", "hi", mode=mode, outcome="review",
            style=styled(format_followed=False)),
        run("fleurs-te_in-1", "fleurs-te_in-1", "te", mode=mode, outcome="review",
            style=styled(length_followed=False, after=13)),
        run("fleurs-te_in-2", "fleurs-te_in-2", "te", mode=mode, outcome="review",
            style=styled(applied=False, notice="rewrite.failed")),
        run("fleurs-te_in-3", "fleurs-te_in-3", "te", mode=mode, outcome="review",
            style=styled(violations=["number-changed"])),
        run("fleurs-hi_in-1~noise-snr10", "fleurs-hi_in-1", "hi", mode=mode, variant="noise-snr10", outcome="review",
            style=styled()),
    ]
    return report("fixture", "transcribe", mode, identifier, runs,
                  [{"name": "fleurs-test", "runs": 6, "sha256": "a" * 64}])


if __name__ == "__main__":
    for name, data in [("evaluation-report.json", transcription()),
                       ("evaluation-report-translation.json", translation()),
                       ("evaluation-report-style.json", style())]:
        (HERE / name).write_text(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
                                 encoding="utf-8")
        print(f"wrote {name}")
