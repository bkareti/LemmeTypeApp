#!/usr/bin/env python3
"""Release check (E2-S10): compares benchmark reports with the thresholds.

    python3 scripts/check-performance-thresholds.py build/benchmarks

Reads every <engine>.json written by DictationBenchmark and the limits in
docs/testing/performance-thresholds.json. Exits 1 if any metric is beyond its
threshold (a regression), 2 if there is nothing to check. Thresholds marked
"Proposed" still fail the check; their status is printed so a product owner
can see they are not yet approved.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
THRESHOLDS = ROOT / "docs/testing/performance-thresholds.json"


def metric(report, path):
    value = report
    for key in path.split("."):
        value = value[key]
    return float(value)


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    config = json.loads(THRESHOLDS.read_text())
    reports = sorted(pathlib.Path(argv[1]).glob("*.json"))
    if not reports:
        print(f"error: no benchmark reports in {argv[1]}", file=sys.stderr)
        return 2
    print(f"Thresholds: {config['status']} ({config.get('approvedBy') or 'not yet approved'})")
    failures = 0
    for path in reports:
        report = json.loads(path.read_text())
        engine = report["engine"]
        limits = {**config["default"], **config.get("engines", {}).get(engine, {})}
        for name, limit in sorted(limits.items()):
            value = metric(report, name)
            ok = value <= limit
            failures += 0 if ok else 1
            print(f"  {'ok  ' if ok else 'FAIL'} {engine:14} {name:34} {value:10.3f} <= {limit}")
    if failures:
        print(f"error: {failures} metric(s) beyond threshold", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
