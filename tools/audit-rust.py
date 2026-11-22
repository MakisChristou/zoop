#!/usr/bin/env python3
"""Fail on new Rust advisories; verify narrowly scoped, dated exceptions."""
import datetime as dt
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
# Exact lockfile versions; exceptions must be revisited after any dependency change.
EXCEPTIONS = {
    ('RUSTSEC-2023-0071', 'rsa', '0.9.10'): 'unreachable',
    ('RUSTSEC-2026-0459', 'libsqlite3-sys', '0.30.1'): 'unreachable',
    ('RUSTSEC-2026-0543', 'chrono', '0.4.45'): 'unmaintained',
}
REVIEW_BY = dt.date(2027, 2, 22)


def evaluate(report, reachable, today):
    failures = []
    reviewed = []
    findings = [('vulnerability', x) for x in report['vulnerabilities']['list']]
    findings += [(kind, x) for kind, entries in report.get('warnings', {}).items() for x in entries]
    for kind, item in findings:
        advisory = item.get('advisory') or {}
        package = item['package']
        key = (advisory.get('id'), package['name'], package['version'])
        exception = EXCEPTIONS.get(key)
        unreachable = (package['name'], package['version']) not in reachable
        accepted = today < REVIEW_BY and (
            (exception == 'unreachable' and unreachable)
            or (exception == 'unmaintained' and kind == 'unmaintained')
        )
        message = f"{key[0] or kind}: {package['name']} {package['version']}"
        if accepted:
            reviewed.append(f'{message} — reviewed {exception}; expires {REVIEW_BY}')
        else:
            failures.append(message)
    return failures, reviewed


def main():
    scan = subprocess.run(['cargo', 'audit', '--json', '--deny', 'warnings'],
                          cwd=ROOT / 'server', capture_output=True, text=True)
    if scan.returncode not in (0, 1):
        sys.exit(scan.stderr or 'Rust advisory scan failed')
    report = json.loads(scan.stdout)  # Missing/invalid scan output must fail closed.
    if not report.get('database', {}).get('last-updated'):
        sys.exit('Advisory database metadata missing')
    tree = subprocess.check_output(
        ['cargo', 'tree', '--locked', '--workspace', '--all-features', '--target', 'all',
         '--prefix', 'none', '--format', '{p}'], cwd=ROOT / 'server', text=True)
    reachable = {(parts[0], parts[1][1:]) for line in tree.splitlines()
                 if len(parts := line.split()) >= 2 and parts[1].startswith('v')}
    if not reachable:
        sys.exit('Dependency graph is empty')
    failures, reviewed = evaluate(report, reachable, dt.datetime.now(dt.timezone.utc).date())
    for message in reviewed:
        print('REVIEWED:', message)
    for message in failures:
        print('FAIL:', message)
    if failures:
        sys.exit(1)
    print('No unreviewed Rust advisories. Reviewed findings remain visible above.')


if __name__ == '__main__':
    main()
