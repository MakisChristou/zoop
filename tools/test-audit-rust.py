#!/usr/bin/env python3
import datetime as dt
import importlib.util
from pathlib import Path
import unittest
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('audit', Path(__file__).with_name('audit-rust.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def report(advisory='RUSTSEC-2023-0071', package='rsa', version='0.9.10', kind='vulnerability'):
    item = {'advisory': {'id': advisory}, 'package': {'name': package, 'version': version}}
    return {'vulnerabilities': {'list': [item] if kind == 'vulnerability' else []},
            'warnings': {} if kind == 'vulnerability' else {kind: [item]}}


class AuditPolicyTests(unittest.TestCase):
    def check(self, data, reachable=(), today=dt.date(2026, 11, 22)):
        return audit.evaluate(data, set(reachable), today)[0]

    def test_unreachable_lockfile_package_is_reviewed(self):
        self.assertFalse(self.check(report()))

    def test_feature_change_makes_known_advisory_fail(self):
        self.assertTrue(self.check(report(), [('rsa', '0.9.10')]))

    def test_new_advisory_or_version_requires_review(self):
        self.assertTrue(self.check(report(advisory='RUSTSEC-NEW')))
        self.assertTrue(self.check(report(version='0.9.11')))

    def test_exceptions_expire(self):
        self.assertTrue(self.check(report(), today=audit.REVIEW_BY))

    def test_maintenance_exception_cannot_hide_vulnerability(self):
        args = dict(advisory='RUSTSEC-2026-0543', package='chrono', version='0.4.45')
        self.assertFalse(self.check(report(**args, kind='unmaintained')))
        self.assertTrue(self.check(report(**args)))

    def test_unrecognized_warning_is_failure(self):
        self.assertTrue(self.check(report(advisory='new', kind='unsound')))


if __name__ == '__main__':
    unittest.main()
