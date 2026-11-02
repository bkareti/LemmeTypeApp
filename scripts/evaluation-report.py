#!/usr/bin/env python3
"""Evaluation reports (docs/testing/evaluation-harness.md).

  scripts/evaluation-report.py REPORT_OR_FOLDER... [--out DIR] [--baseline REPORT_OR_FOLDER]
                               [--wer-tolerance 0.02] [--fail-on-regression]

Reads the EvaluationReport JSON files the Swift harness writes (build/evaluation/) and
writes three files to --out (default build/evaluation/report):

  summary.json  accuracy, failures, hallucinations, and speed by language, variant, and tag
  junit.xml     one test case per run (failures: no text from speech, hallucinations) and
                one per baseline check (regressions)
  index.html    a self-contained dashboard: no scripts, no external requests

Word and character error rates are pooled: total edits over total reference length, not
an average of per-run rates. Only human references count (review != unverified). Reports
hold metrics and case ids only, never text, and so do these outputs. Standard library only.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEFAULT_OUT = REPO / "build" / "evaluation" / "report"
REPORT_KEYS = {"schema", "label", "task", "writingMode", "runs"}
SCHEMA = 1
MINIMUM_GROUP_RUNS = 10
LATENCY_TOLERANCE = 0.2  # a fifth slower at p95, and at least LATENCY_FLOOR seconds
LATENCY_FLOOR = 0.2


# MARK: Loading


def load_reports(paths: list[Path]) -> list[dict]:
    reports = []
    for path in paths:
        files = sorted(path.glob("*.json")) if path.is_dir() else [path]
        for file in files:
            data = json.loads(file.read_text(encoding="utf-8"))
            if isinstance(data, dict) and REPORT_KEYS <= data.keys():
                if data["schema"] != SCHEMA:
                    raise SystemExit(f"error: {file}: report schema {data['schema']} is not {SCHEMA}")
                reports.append(data)
    return reports


def key(report: dict) -> tuple[str, str, str]:
    return report["label"], report["task"], report["writingMode"]


def variant(run: dict) -> str:
    return run.get("variantID") or "original"


def language(run: dict) -> str:
    return run["result"]["language"].split("-")[0].lower()


def has_speech(run: dict) -> bool:
    return run["result"]["score"]["words"]["referenceLength"] > 0


# MARK: Aggregation


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(math.ceil(fraction * len(ordered))) - 1)]


def rate(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def aggregate(runs: list[dict]) -> dict:
    """Pooled metrics for a group of runs."""
    speech = [run for run in runs if has_speech(run)]
    silent = [run for run in runs if not has_speech(run)]

    def pooled(kind: str, field: str | None = None) -> float | None:
        total = sum(run["result"]["score"][kind]["referenceLength"] for run in speech)
        parts = ("substitutions", "deletions", "insertions") if field is None else (field,)
        edits = sum(run["result"]["score"][kind][part] for run in speech for part in parts)
        return rate(edits, total)

    latencies = [run["result"]["stopToDeliverySeconds"] for run in runs]
    factors = [
        run["result"]["inferenceSeconds"] / run["result"]["audioSeconds"]
        for run in runs
        if run["result"]["audioSeconds"] > 0
    ]
    return {
        "runs": len(runs),
        "speechRuns": len(speech),
        "noSpeechRuns": len(silent),
        "audioMinutes": round(sum(run["result"]["audioSeconds"] for run in runs) / 60, 2),
        "wordErrorRate": pooled("words"),
        "characterErrorRate": pooled("characters"),
        "insertionRate": pooled("words", "insertions"),
        "noTextRate": rate(sum(not run["result"]["producedText"] for run in speech), len(speech)),
        "textWithoutSpeechRate": rate(sum(run["result"]["score"]["textWithoutSpeech"] for run in silent), len(silent)),
        "repetitionLoopRate": rate(sum(run["result"]["score"]["repetitionLoop"] for run in runs), len(runs)),
        "latencyP50Seconds": percentile(latencies, 0.5),
        "latencyP95Seconds": percentile(latencies, 0.95),
        "realTimeFactorMean": sum(factors) / len(factors) if factors else None,
    }


def grouped(runs: list[dict], by) -> dict[str, dict]:
    groups: dict[str, list[dict]] = {}
    for run in runs:
        groups.setdefault(by(run), []).append(run)
    return {name: aggregate(groups[name]) for name in sorted(groups)}


def run_wer(run: dict) -> float:
    words = run["result"]["score"]["words"]
    edits = words["substitutions"] + words["deletions"] + words["insertions"]
    return edits / words["referenceLength"] if words["referenceLength"] else (1.0 if edits else 0.0)


def run_cer(run: dict) -> float:
    characters = run["result"]["score"]["characters"]
    edits = characters["substitutions"] + characters["deletions"] + characters["insertions"]
    return edits / characters["referenceLength"] if characters["referenceLength"] else (1.0 if edits else 0.0)


def problem(run: dict) -> str | None:
    """Why a run fails on its own, without any accuracy threshold."""
    result = run["result"]
    if has_speech(run) and not result["producedText"]:
        return f"no text from speech ({result['outcome']})"
    if result["score"]["textWithoutSpeech"]:
        return "text from audio without speech"
    if result["score"]["repetitionLoop"]:
        return "repetition loop"
    return None


def ground_truth(report: dict) -> list[dict]:
    return [run for run in report["runs"] if run["review"] != "unverified"]


def summarize(report: dict, runs: list[dict] | None = None) -> dict:
    runs = ground_truth(report) if runs is None else runs
    speech = [run for run in runs if has_speech(run)]
    worst = sorted(speech, key=lambda run: (-run_wer(run), run["id"]))[:20]
    return {
        "label": report["label"],
        "engine": report.get("engine"),
        "task": report["task"],
        "writingMode": report["writingMode"],
        "date": report.get("date"),
        "hardwareModel": report.get("hardwareModel"),
        "physicalMemoryGB": report.get("physicalMemoryGB"),
        "operatingSystem": report.get("operatingSystem"),
        "warmUpSeconds": report.get("warmUpSeconds"),
        "peakMemoryIncreaseMB": report.get("peakMemoryIncreaseMB"),
        "corpora": report.get("corpora", []),
        "skipped": report.get("skipped", {}),
        "unverifiedRuns": len(report["runs"]) - len(ground_truth(report)),
        "overall": aggregate(runs),
        "byLanguage": grouped(runs, language),
        "byVariant": grouped(runs, variant),
        "byLanguageAndVariant": grouped(runs, lambda run: f"{language(run)} · {variant(run)}"),
        "byNumbers": grouped(speech, lambda run: "has digits" if "numbers" in run["tags"] else "no digits"),
        "worst": [
            {"id": run["id"], "language": language(run), "variant": variant(run), "wordErrorRate": run_wer(run),
             "characterErrorRate": run_cer(run), "outcome": run["result"]["outcome"]}
            for run in worst
        ],
        "problems": [{"id": run["id"], "problem": problem(run)} for run in runs if problem(run)],
    }


# MARK: Baseline comparison


def compare(current: dict, baseline: dict, wer_tolerance: float) -> dict:
    """Like for like: only case ids in both reports, so a corpus change cannot look like a regression."""
    now = {run["id"]: run for run in ground_truth(current)}
    then = {run["id"]: run for run in ground_truth(baseline)}
    common = sorted(now.keys() & then.keys())
    before = summarize(baseline, [then[name] for name in common])
    after = summarize(current, [now[name] for name in common])
    checks = []

    def check(scope: str, metric: str, old, new, regressed: bool, detail: str) -> None:
        checks.append({"scope": scope, "metric": metric, "baseline": old, "current": new, "regressed": regressed,
                       "detail": detail})

    groups = [("overall", before["overall"], after["overall"])]
    groups += [(f"language {name}", before["byLanguage"].get(name), stats)
               for name, stats in after["byLanguage"].items()]
    groups += [(f"variant {name}", before["byVariant"].get(name), stats)
               for name, stats in after["byVariant"].items()]
    for scope, old, new in groups:
        if not old or new["runs"] < MINIMUM_GROUP_RUNS:
            continue
        for metric in ("wordErrorRate", "characterErrorRate"):
            if old[metric] is not None and new[metric] is not None:
                change = new[metric] - old[metric]
                check(scope, metric, old[metric], new[metric], change > wer_tolerance,
                      f"{change * 100:+.1f} points (tolerance {wer_tolerance * 100:.1f})")
        for metric in ("noTextRate", "textWithoutSpeechRate", "repetitionLoopRate"):
            if old[metric] is not None and new[metric] is not None:
                check(scope, metric, old[metric], new[metric], new[metric] > old[metric],
                      f"{(new[metric] - old[metric]) * 100:+.1f} points (any rise fails)")
        if old["latencyP95Seconds"] and new["latencyP95Seconds"]:
            change = new["latencyP95Seconds"] - old["latencyP95Seconds"]
            check(scope, "latencyP95Seconds", old["latencyP95Seconds"], new["latencyP95Seconds"],
                  change > max(LATENCY_FLOOR, old["latencyP95Seconds"] * LATENCY_TOLERANCE),
                  f"{change:+.2f} s (tolerance max({LATENCY_FLOOR} s, {LATENCY_TOLERANCE:.0%}))")
    newly = sorted(name for name in common if problem(now[name]) and not problem(then[name]))
    for name in newly:
        check(f"case {name}", "problem", None, problem(now[name]), True, "passed in the baseline")
    corpora_match = {corpus.get("sha256") for corpus in current.get("corpora", [])} == {
        corpus.get("sha256") for corpus in baseline.get("corpora", [])}
    return {
        "label": current["label"], "task": current["task"], "writingMode": current["writingMode"],
        "baselineDate": baseline.get("date"), "commonRuns": len(common),
        "onlyInCurrent": len(now.keys() - then.keys()), "onlyInBaseline": len(then.keys() - now.keys()),
        "corporaMatch": corpora_match, "regressions": sum(item["regressed"] for item in checks), "checks": checks,
    }


# MARK: JUnit


def junit(reports: list[dict], comparisons: list[dict]) -> str:
    suites = ElementTree.Element("testsuites", name="LemmeType evaluation")
    for report in reports:
        runs = ground_truth(report)
        suite = ElementTree.SubElement(suites, "testsuite", name=f"{report['label']} {report['task']} {report['writingMode']}")
        properties = ElementTree.SubElement(suite, "properties")
        for name in ("engine", "hardwareModel", "operatingSystem", "date"):
            ElementTree.SubElement(properties, "property", name=name, value=str(report.get(name, "")))
        failures = 0
        for run in runs:
            case = ElementTree.SubElement(
                suite, "testcase", classname=f"{report['label']}.{report['task']}.{language(run)}.{variant(run)}",
                name=run["id"], time=f"{run['result']['stopToDeliverySeconds']:.3f}")
            reason = problem(run)
            if reason:
                failures += 1
                ElementTree.SubElement(case, "failure", message=reason, type=run["result"]["outcome"])
            else:
                ElementTree.SubElement(case, "system-out").text = (
                    f"WER {run_wer(run):.3f} CER {run_cer(run):.3f}")
        suite.set("tests", str(len(runs)))
        suite.set("failures", str(failures))
    for comparison in comparisons:
        suite = ElementTree.SubElement(
            suites, "testsuite", name=f"regressions {comparison['label']} {comparison['task']} {comparison['writingMode']}")
        for item in comparison["checks"]:
            case = ElementTree.SubElement(suite, "testcase", classname=item["scope"], name=item["metric"])
            if item["regressed"]:
                ElementTree.SubElement(case, "failure", message=item["detail"], type="regression")
        suite.set("tests", str(len(comparison["checks"])))
        suite.set("failures", str(comparison["regressions"]))
    ElementTree.indent(suites)
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ElementTree.tostring(suites, encoding="unicode") + "\n"


# MARK: HTML


METRIC_NAMES = {
    "wordErrorRate": "Word error rate",
    "characterErrorRate": "Character error rate",
    "noTextRate": "No text from speech",
    "textWithoutSpeechRate": "Text from silence",
    "repetitionLoopRate": "Repetition loops",
    "latencyP95Seconds": "p95 latency",
    "problem": "Newly failing case",
}


def percent(value: float | None) -> str:
    return "—" if value is None else f"{value * 100:.1f} %"


def seconds(value: float | None) -> str:
    return "—" if value is None else f"{value:.2f} s"


def bar(value: float | None) -> str:
    """A thin magnitude bar for an error rate; the number beside it carries the value."""
    if value is None:
        return ""
    width = max(0.0, min(1.0, value)) * 100
    return f'<span class="bar" title="{percent(value)}"><span style="width:{width:.1f}%"></span></span>'


def status(ok: bool, good: str, bad: str) -> str:
    return (f'<span class="status good">✓ {html.escape(good)}</span>' if ok
            else f'<span class="status critical">✕ {html.escape(bad)}</span>')


def group_table(title: str, groups: dict[str, dict]) -> str:
    rows = "".join(
        f"<tr><th scope=row>{html.escape(name)}</th><td>{stats['runs']}</td>"
        f"<td class=num>{percent(stats['wordErrorRate'])}</td><td>{bar(stats['wordErrorRate'])}</td>"
        f"<td class=num>{percent(stats['characterErrorRate'])}</td><td>{bar(stats['characterErrorRate'])}</td>"
        f"<td class=num>{percent(stats['noTextRate'])}</td><td class=num>{percent(stats['textWithoutSpeechRate'])}</td>"
        f"<td class=num>{seconds(stats['latencyP95Seconds'])}</td></tr>"
        for name, stats in groups.items())
    return (f"<h3>{html.escape(title)}</h3><div class=scroll><table><thead><tr><th scope=col>Group</th>"
            "<th scope=col>Runs</th><th scope=col colspan=2>WER</th><th scope=col colspan=2>CER</th>"
            "<th scope=col>No text</th><th scope=col>Text from silence</th><th scope=col>p95 latency</th>"
            f"</tr></thead><tbody>{rows}</tbody></table></div>")


def tile(label: str, value: str, note: str = "") -> str:
    return (f'<div class=tile><div class=tile-label>{html.escape(label)}</div><div class=tile-value>{value}</div>'
            f'<div class=tile-note>{html.escape(note)}</div></div>')


def report_section(summary: dict, comparison: dict | None) -> str:
    overall = summary["overall"]
    problems = len(summary["problems"])
    corpus = ", ".join(f"{c['name']} ({c['sha256'][:10]}, {c['runs']} runs)" for c in summary["corpora"])
    skipped = ", ".join(f"{name}: {count}" for name, count in sorted(summary["skipped"].items()) if count) or "none"
    parts = [
        f"<section><h2>{html.escape(summary['label'])} · {html.escape(summary['task'])} · "
        f"{html.escape(summary['writingMode'])}</h2>",
        f"<p class=meta>{html.escape(str(summary['date']))} · {html.escape(str(summary['hardwareModel']))} · "
        f"{summary['physicalMemoryGB']} GB · {html.escape(str(summary['operatingSystem']))}<br>"
        f"Corpus: {html.escape(corpus)} · skipped: {html.escape(skipped)} · "
        f"unverified runs left out: {summary['unverifiedRuns']}</p>",
        "<div class=tiles>",
        tile("Word error rate", percent(overall["wordErrorRate"]), f"{overall['speechRuns']} speech runs"),
        tile("Character error rate", percent(overall["characterErrorRate"]), "pooled"),
        tile("Runs with a problem", str(problems), "none" if problems == 0 else "listed below"),
        tile("Text from silence", percent(overall["textWithoutSpeechRate"]), f"{overall['noSpeechRuns']} no-speech runs"),
        tile("p95 latency", seconds(overall["latencyP95Seconds"]), f"p50 {seconds(overall['latencyP50Seconds'])}"),
        tile("Real-time factor", "—" if overall["realTimeFactorMean"] is None else f"{overall['realTimeFactorMean']:.2f}×",
             f"warm-up {seconds(summary['warmUpSeconds'])} · +{summary['peakMemoryIncreaseMB'] or 0:.0f} MB"),
        "</div>",
    ]
    if comparison:
        regressions = comparison["regressions"]
        parts.append(
            f"<h3>Against the baseline of {html.escape(str(comparison['baselineDate']))}</h3><p>"
            + status(regressions == 0, "no regressions", f"{regressions} regression(s)")
            + f" · {comparison['commonRuns']} runs in both · {comparison['onlyInCurrent']} new · "
            f"{comparison['onlyInBaseline']} gone"
            + ("" if comparison["corporaMatch"] else " · <strong>the corpus changed</strong>; common runs only")
            + "</p>")
        failed = [item for item in comparison["checks"] if item["regressed"]]
        if failed:
            rows = "".join(
                f"<tr><th scope=row>{html.escape(item['scope'])}</th>"
                f"<td>{html.escape(METRIC_NAMES.get(item['metric'], item['metric']))}</td>"
                f"<td>{html.escape(item['detail'])}</td></tr>" for item in failed)
            parts.append("<div class=scroll><table><thead><tr><th scope=col>Scope</th><th scope=col>Metric</th>"
                         f"<th scope=col>Change</th></tr></thead><tbody>{rows}</tbody></table></div>")
    parts.append(group_table("By language", summary["byLanguage"]))
    parts.append(group_table("By variant", summary["byVariant"]))
    parts.append(group_table("By language and variant", summary["byLanguageAndVariant"]))
    parts.append(group_table("References with and without digits", summary["byNumbers"]))
    if summary["problems"]:
        rows = "".join(f"<tr><th scope=row><code>{html.escape(item['id'])}</code></th><td>"
                       f"{html.escape(item['problem'])}</td></tr>" for item in summary["problems"][:200])
        parts.append(f"<h3>Runs with a problem ({problems})</h3><div class=scroll><table><thead><tr>"
                     f"<th scope=col>Case</th><th scope=col>Problem</th></tr></thead><tbody>{rows}</tbody></table></div>")
    rows = "".join(
        f"<tr><th scope=row><code>{html.escape(item['id'])}</code></th><td>{html.escape(item['language'])}</td>"
        f"<td>{html.escape(item['variant'])}</td><td class=num>{percent(item['wordErrorRate'])}</td>"
        f"<td class=num>{percent(item['characterErrorRate'])}</td><td>{html.escape(item['outcome'])}</td></tr>"
        for item in summary["worst"])
    parts.append("<h3>Highest word error rate</h3><div class=scroll><table><thead><tr><th scope=col>Case</th>"
                 "<th scope=col>Language</th><th scope=col>Variant</th><th scope=col>WER</th><th scope=col>CER</th>"
                 f"<th scope=col>Outcome</th></tr></thead><tbody>{rows}</tbody></table></div></section>")
    return "".join(parts)


STYLE = """
:root{color-scheme:light;--page:#f9f9f7;--surface:#fcfcfb;--ink:#0b0b0b;--ink-2:#52514e;--line:#e4e3df;
--bar:#2a78d6;--bar-track:#eceae6;--good:#0ca30c;--good-ink:#006300;--critical:#d03b3b}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){color-scheme:dark;--page:#0d0d0d;
--surface:#1a1a19;--ink:#f0efec;--ink-2:#c3c2b7;--line:#33332f;--bar:#3987e5;--bar-track:#2a2a27;
--good:#0ca30c;--good-ink:#5fd35f;--critical:#e66767}}
:root[data-theme=dark]{color-scheme:dark;--page:#0d0d0d;--surface:#1a1a19;--ink:#f0efec;--ink-2:#c3c2b7;
--line:#33332f;--bar:#3987e5;--bar-track:#2a2a27;--good:#0ca30c;--good-ink:#5fd35f;--critical:#e66767}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);
font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}h1{font-size:24px;margin:0 0 4px}
h2{font-size:19px;margin:32px 0 4px}h3{font-size:15px;margin:24px 0 8px;color:var(--ink-2)}
.meta,.lede{color:var(--ink-2);margin:0 0 12px}section{background:var(--surface);border:1px solid var(--line);
border-radius:12px;padding:4px 20px 20px;margin-top:20px}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}
.tile{border:1px solid var(--line);border-radius:10px;padding:12px}.tile-label{color:var(--ink-2);font-size:13px}
.tile-value{font-size:26px;font-weight:600;font-variant-numeric:tabular-nums}.tile-note{color:var(--ink-2);font-size:12px}
.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}
th,td{text-align:left;padding:6px 10px;border-bottom:1px solid var(--line);white-space:nowrap}
thead th{color:var(--ink-2);font-weight:500;font-size:13px}td.num{text-align:right}
.bar{display:inline-block;width:120px;height:8px;border-radius:4px;background:var(--bar-track);vertical-align:middle}
.bar span{display:block;height:8px;border-radius:4px;background:var(--bar)}
.status{font-weight:600}.status.good{color:var(--good-ink)}.status.critical{color:var(--critical)}
code{font:12px ui-monospace,SFMono-Regular,Menlo,monospace}
"""


def dashboard(summaries: list[dict], comparisons: list[dict]) -> str:
    by_key = {(c["label"], c["task"], c["writingMode"]): c for c in comparisons}
    sections = "".join(
        report_section(summary, by_key.get((summary["label"], summary["task"], summary["writingMode"])))
        for summary in summaries)
    return (
        "<!doctype html><html lang=en><head><meta charset=utf-8>"
        "<meta name=viewport content='width=device-width,initial-scale=1'>"
        f"<title>LemmeType evaluation</title><style>{STYLE}</style></head><body><main>"
        "<h1>LemmeType evaluation</h1><p class=lede>Pooled word and character error rates against human "
        "references; case ids point into <code>docs/testing/corpus/</code>. Metrics only: no audio or text.</p>"
        f"{sections}</main></body></html>\n")


# MARK: Command line


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--wer-tolerance", type=float, default=0.02, help="WER/CER rise that counts (0.02 = 2 points)")
    parser.add_argument("--fail-on-regression", action="store_true")
    args = parser.parse_args(argv)

    reports = load_reports(args.reports)
    if not reports:
        print("error: no evaluation reports found", file=sys.stderr)
        return 1
    baselines = {key(report): report for report in load_reports([args.baseline])} if args.baseline else {}
    comparisons = [compare(report, baselines[key(report)], args.wer_tolerance)
                   for report in reports if key(report) in baselines]
    summaries = [summarize(report) for report in reports]

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "summary.json").write_text(
        json.dumps({"reports": summaries, "comparisons": comparisons}, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")
    (args.out / "junit.xml").write_text(junit(reports, comparisons), encoding="utf-8")
    (args.out / "index.html").write_text(dashboard(summaries, comparisons), encoding="utf-8")

    for summary in summaries:
        overall = summary["overall"]
        print(f"{summary['label']} {summary['task']} {summary['writingMode']}: {overall['runs']} runs, "
              f"WER {percent(overall['wordErrorRate'])}, CER {percent(overall['characterErrorRate'])}, "
              f"{len(summary['problems'])} with a problem")
    regressions = sum(comparison["regressions"] for comparison in comparisons)
    if comparisons:
        print(f"{regressions} regression(s) against the baseline")
    print(f"Wrote {args.out / 'index.html'}, junit.xml, summary.json")
    return 1 if args.fail_on_regression and regressions else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
