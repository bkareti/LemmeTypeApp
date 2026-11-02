#!/usr/bin/env python3
"""Fixture tests for scripts/evaluation-report.py. The fixture is shared with the Swift
EvaluationReportTests, so both sides agree on the report format."""

import copy
import importlib.util
import io
import json
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "scripts" / "tests" / "fixtures"
FIXTURE = FIXTURES / "evaluation-report.json"
TRANSLATION = FIXTURES / "evaluation-report-translation.json"
STYLE = FIXTURES / "evaluation-report-style.json"
spec = importlib.util.spec_from_file_location("evaluation_report", REPO / "scripts" / "evaluation-report.py")
report_tool = importlib.util.module_from_spec(spec)
sys.modules["evaluation_report"] = report_tool
spec.loader.exec_module(report_tool)


def fixture() -> dict:
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def many(report: dict, copies: int) -> dict:
    """The fixture's verified runs repeated under new ids, so groups are big enough to compare."""
    bigger = copy.deepcopy(report)
    runs = [run for run in report["runs"] if run["review"] != "unverified"]
    bigger["runs"] = []
    for index in range(copies):
        for run in runs:
            clone = copy.deepcopy(run)
            clone["id"] = f"{run['id']}#{index}"
            clone["result"]["id"] = clone["id"]
            bigger["runs"].append(clone)
    return bigger


class SummaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.summary = report_tool.summarize(fixture())

    def test_error_rates_are_pooled_over_verified_speech_runs(self) -> None:
        overall = self.summary["overall"]
        # Speech runs: 1+3+2+5+8+2 = 21 word edits over 8+8+6+5+4+8 = 39 reference words.
        self.assertAlmostEqual(overall["wordErrorRate"], 21 / 39)
        # Characters: 2+6+4+30+(2+30)+5 = 79 edits over 40+40+50+30+25+40 = 225.
        self.assertAlmostEqual(overall["characterErrorRate"], 79 / 225)
        self.assertEqual(overall["runs"], 8)
        self.assertEqual(self.summary["unverifiedRuns"], 1)

    def test_failures_and_hallucinations_are_counted_by_kind(self) -> None:
        overall = self.summary["overall"]
        self.assertAlmostEqual(overall["noTextRate"], 1 / 6)
        self.assertAlmostEqual(overall["textWithoutSpeechRate"], 1 / 2)
        self.assertAlmostEqual(overall["repetitionLoopRate"], 1 / 8)
        self.assertEqual(
            {item["id"]: item["problem"] for item in self.summary["problems"]},
            {
                "fleurs-te_in-2": "no text from speech (recognition.no-speech)",
                "fleurs-te_in-3": "repetition loop",
                "noise-loud@te": "text from audio without speech",
            },
        )

    def test_groups(self) -> None:
        self.assertEqual(sorted(self.summary["byLanguage"]), ["hi", "te"])
        self.assertEqual(sorted(self.summary["byVariant"]), ["noise-snr10", "original"])
        self.assertIn("hi · noise-snr10", self.summary["byLanguageAndVariant"])
        self.assertEqual(self.summary["byNumbers"]["has digits"]["runs"], 1)
        self.assertAlmostEqual(self.summary["byLanguage"]["te"]["wordErrorRate"], 15 / 15)

    def test_worst_runs_come_first(self) -> None:
        self.assertEqual(self.summary["worst"][0]["id"], "fleurs-te_in-3")
        self.assertEqual(self.summary["worst"][0]["wordErrorRate"], 2.0)

    def test_percentile(self) -> None:
        self.assertEqual(report_tool.percentile([3, 1, 2, 4], 0.5), 2)
        self.assertEqual(report_tool.percentile(list(range(1, 101)), 0.95), 95)
        self.assertIsNone(report_tool.percentile([], 0.95))


class ModeTests(unittest.TestCase):
    def test_chrf_matches_the_worked_example_shared_with_swift(self) -> None:
        cat_hat = {"hypothesis": [6, 5, 4, 3, 2, 1], "reference": [6, 5, 4, 3, 2, 1], "matches": [5, 3, 1, 0, 0, 0]}
        self.assertAlmostEqual(report_tool.chrf(cat_hat), 100 * (5 / 6 + 3 / 5 + 1 / 4) / 6)
        empty = {"hypothesis": [0] * 6, "reference": [0] * 6, "matches": [0] * 6}
        self.assertEqual(report_tool.chrf(empty), 100.0)
        self.assertEqual(report_tool.chrf({**empty, "reference": [3, 2, 1, 0, 0, 0]}), 0.0)

    def test_numbers_normalized_wer_is_pooled_beside_the_literal_one(self) -> None:
        overall = report_tool.summarize(fixture())["overall"]
        # The numbers case drops from 3 to 1 edit once "1911" and "nineteen eleven" compare equal.
        self.assertAlmostEqual(overall["wordErrorRate"], 21 / 39)
        self.assertAlmostEqual(overall["wordErrorRateNumbersNormalized"], 19 / 39)

    def test_translation_is_pooled_and_numbers_or_negation_changes_are_problems(self) -> None:
        summary = report_tool.summarize(json.loads(TRANSLATION.read_text(encoding="utf-8")))
        translation = summary["overall"]["translation"]
        self.assertEqual(translation["runs"], 6)
        pooled = report_tool.pooled_statistics(
            [run for run in json.loads(TRANSLATION.read_text(encoding="utf-8"))["runs"] if report_tool.has_speech(run)])
        self.assertEqual(pooled["hypothesis"][0], 6 + 20 + 20 + 0 + 20 + 20)
        self.assertAlmostEqual(translation["chrF"], report_tool.chrf(pooled))
        self.assertAlmostEqual(translation["criticalViolationRate"], 2 / 6)
        self.assertAlmostEqual(translation["violationRates"]["name-changed"], 2 / 6)
        problems = {item["id"]: item["problem"] for item in summary["problems"]}
        self.assertEqual(problems["fleurs-hi_in-2"], "translation changed a negation")
        self.assertEqual(problems["fleurs-te_in-1"], "translation changed a number")
        self.assertNotIn("fleurs-te_in-3", problems)  # a name difference alone is reported, not a failure
        self.assertIn("translation", summary["byLanguage"]["hi"])

    def test_style_compliance_is_reported_and_a_changed_fact_is_a_problem(self) -> None:
        summary = report_tool.summarize(json.loads(STYLE.read_text(encoding="utf-8")))
        style = summary["overall"]["style"]
        self.assertAlmostEqual(style["appliedRate"], 5 / 6)
        self.assertAlmostEqual(style["formatFollowedRate"], 4 / 5)
        self.assertAlmostEqual(style["lengthFollowedRate"], 4 / 5)
        self.assertAlmostEqual(style["violationRate"], 1 / 5)
        self.assertEqual(style["notices"], {"rewrite.failed": 1})
        self.assertEqual(summary["style"], "neutral-bullet-list-concise")
        problems = {item["id"]: item["problem"] for item in summary["problems"]}
        self.assertEqual(problems, {"fleurs-te_in-3": "an applied rewrite changed number-changed"})

    def test_a_falling_chrf_regresses(self) -> None:
        baseline = many(json.loads(TRANSLATION.read_text(encoding="utf-8")), 3)
        current = copy.deepcopy(baseline)
        for run in current["runs"]:
            if run["result"]["translation"]:
                statistics = run["result"]["translation"]["characterNGrams"]
                statistics["matches"] = [max(0, value - 2) for value in statistics["matches"]]
        result = report_tool.compare(current, baseline, 0.02)
        failed = {(item["scope"], item["metric"]) for item in result["checks"] if item["regressed"]}
        self.assertIn(("overall", "chrF"), failed)

    def test_the_dashboard_shows_translation_and_style_sections(self) -> None:
        translation = report_tool.summarize(json.loads(TRANSLATION.read_text(encoding="utf-8")))
        style = report_tool.summarize(json.loads(STYLE.read_text(encoding="utf-8")))
        page = report_tool.dashboard([translation, style], [])
        self.assertIn("Translation to English", page)
        self.assertIn("Style · neutral-bullet-list-concise", page)
        self.assertIn("WER, numbers normalized", page)
        self.assertIn("Tone is not checked by rule", page)

    def test_reports_are_keyed_by_mode(self) -> None:
        folder = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-evaluation-")
        self.addCleanup(folder.cleanup)
        for path in (FIXTURE, STYLE):
            (Path(folder.name) / path.name).write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        keys = {report_tool.key(report) for report in report_tool.load_reports([Path(folder.name)])}
        self.assertEqual(keys, {("fixture", "transcribe", "clean"),
                                ("fixture", "transcribe", "style-neutral-bullet-list-concise")})

    def test_an_old_schema_is_refused(self) -> None:
        folder = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-evaluation-")
        self.addCleanup(folder.cleanup)
        old = fixture()
        old["schema"] = 1
        (Path(folder.name) / "old.json").write_text(json.dumps(old))
        with self.assertRaises(SystemExit):
            report_tool.load_reports([Path(folder.name)])


class ComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        self.baseline = many(fixture(), 3)

    def test_the_same_report_has_no_regressions(self) -> None:
        result = report_tool.compare(self.baseline, copy.deepcopy(self.baseline), 0.02)
        self.assertEqual(result["regressions"], 0)
        self.assertTrue(result["corporaMatch"])
        self.assertGreater(len(result["checks"]), 0)

    def test_a_worse_word_error_rate_beyond_the_tolerance_regresses(self) -> None:
        current = copy.deepcopy(self.baseline)
        for run in current["runs"]:
            if run["result"]["language"] == "hi" and run["result"]["score"]["words"]["referenceLength"]:
                run["result"]["score"]["words"]["substitutions"] += 1
        result = report_tool.compare(current, self.baseline, 0.02)
        failed = {(item["scope"], item["metric"]) for item in result["checks"] if item["regressed"]}
        self.assertIn(("language hi", "wordErrorRate"), failed)
        self.assertIn(("overall", "wordErrorRate"), failed)
        self.assertNotIn(("language te", "wordErrorRate"), failed)
        self.assertEqual(report_tool.compare(current, self.baseline, 0.5)["regressions"], 0)

    def test_a_case_that_newly_fails_is_named(self) -> None:
        current = copy.deepcopy(self.baseline)
        target = next(run for run in current["runs"] if run["id"] == "fleurs-hi_in-1#0")
        target["result"]["producedText"] = False
        target["result"]["outcome"] = "recognition.engine-failure"
        result = report_tool.compare(current, self.baseline, 0.5)
        cases = [item for item in result["checks"] if item["scope"].startswith("case ")]
        self.assertEqual([item["scope"] for item in cases], ["case fleurs-hi_in-1#0"])
        self.assertTrue(cases[0]["regressed"])

    def test_a_changed_corpus_compares_common_runs_only(self) -> None:
        current = copy.deepcopy(self.baseline)
        current["corpora"][0]["sha256"] = "c" * 64
        current["runs"] = current["runs"][:-3]
        result = report_tool.compare(current, self.baseline, 0.02)
        self.assertFalse(result["corporaMatch"])
        self.assertEqual(result["onlyInBaseline"], 3)
        self.assertEqual(result["regressions"], 0)

    def test_small_groups_are_not_compared(self) -> None:
        result = report_tool.compare(fixture(), fixture(), 0.02)
        self.assertEqual([item for item in result["checks"] if item["scope"] != "overall"], [])


class OutputTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-evaluation-")
        self.folder = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_tool(self, *arguments: str) -> int:
        with mock.patch("sys.stdout", io.StringIO()), mock.patch("sys.stderr", io.StringIO()):
            return report_tool.main(list(arguments))

    def test_junit_has_one_case_per_run_and_fails_only_real_problems(self) -> None:
        suites = ElementTree.fromstring(report_tool.junit([fixture()], []))
        suite = suites.find("testsuite")
        self.assertEqual(suite.get("tests"), "8")
        self.assertEqual(suite.get("failures"), "3")
        failed = {case.get("name") for case in suite.iter("testcase") if case.find("failure") is not None}
        self.assertEqual(failed, {"fleurs-te_in-2", "fleurs-te_in-3", "noise-loud@te"})

    def test_junit_lists_regressions_in_their_own_suite(self) -> None:
        baseline = many(fixture(), 3)
        current = copy.deepcopy(baseline)
        for run in current["runs"]:
            run["result"]["score"]["words"]["insertions"] += 2
        comparison = report_tool.compare(current, baseline, 0.02)
        suites = ElementTree.fromstring(report_tool.junit([current], [comparison]))
        regression = [suite for suite in suites.iter("testsuite") if suite.get("name").startswith("regressions")][0]
        self.assertGreater(int(regression.get("failures")), 0)

    def test_the_dashboard_is_self_contained_and_escapes_ids(self) -> None:
        report = fixture()
        report["runs"][0]["id"] = "<b>case</b>"
        page = report_tool.dashboard([report_tool.summarize(report)], [])
        self.assertNotIn("<script", page)
        self.assertNotIn("http", page)
        self.assertNotIn("<b>case</b>", page)
        self.assertIn("&lt;b&gt;case&lt;/b&gt;", page)
        self.assertIn("53.8 %", page)
        self.assertIn("prefers-color-scheme:dark", page)

    def test_the_command_writes_all_three_files_and_skips_its_own_summary(self) -> None:
        out = self.folder / "report"
        (self.folder / "fixture.json").write_text(FIXTURE.read_text(encoding="utf-8"), encoding="utf-8")
        self.assertEqual(self.run_tool(str(self.folder), "--out", str(out)), 0)
        self.assertTrue((out / "index.html").is_file())
        self.assertTrue((out / "junit.xml").is_file())
        summary = json.loads((out / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(len(summary["reports"]), 1)
        (self.folder / "summary.json").write_text((out / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(len(report_tool.load_reports([self.folder])), 1)

    def test_fail_on_regression_sets_the_exit_code(self) -> None:
        baseline = many(fixture(), 3)
        current = copy.deepcopy(baseline)
        for run in current["runs"]:
            run["result"]["score"]["words"]["insertions"] += 2
        (self.folder / "baseline.json").write_text(json.dumps(baseline))
        (self.folder / "current.json").write_text(json.dumps(current))
        out = str(self.folder / "out")
        arguments = [str(self.folder / "current.json"), "--baseline", str(self.folder / "baseline.json"), "--out", out]
        self.assertEqual(self.run_tool(*arguments), 0)
        self.assertEqual(self.run_tool(*arguments, "--fail-on-regression"), 1)

    def test_no_reports_is_an_error(self) -> None:
        self.assertEqual(self.run_tool(str(self.folder)), 1)


if __name__ == "__main__":
    unittest.main()
