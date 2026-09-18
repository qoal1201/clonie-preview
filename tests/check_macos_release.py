"""Release safety checks use mocked Apple tools; they do not prove notarization."""
import argparse
import importlib.util
import json
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'scripts/release/macos.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
DEV = '  1) ' + 'A' * 40 + ' "Apple Development: Test (TEAM)"\n'
DIST = '  2) ' + 'B' * 40 + ' "Developer ID Application: Test (TEAM)"\n'


class ReleaseTests(unittest.TestCase):
    def test_non_app_bundle_rejected_before_signing_or_upload(self):
        for package_type in [None, 'BNDL']:
            with self.subTest(package_type=package_type), tempfile.TemporaryDirectory() as temp:
                app = Path(temp) / 'Clonie.app'
                (app / 'Contents').mkdir(parents=True)
                info = {'CFBundleIdentifier': 'com.local.clonie', 'CFBundleExecutable': 'Clonie'}
                if package_type is not None:
                    info['CFBundlePackageType'] = package_type
                (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
                args = argparse.Namespace(app=app, work=Path(temp) / 'release', identity=None)
                with patch.object(release, 'identity', return_value=('key', 'name')), patch.object(release, 'run') as run:
                    with self.assertRaisesRegex(RuntimeError, 'CFBundlePackageType=APPL'):
                        release.prepare(args)
                    run.assert_not_called()
                self.assertFalse(args.work.exists())

    def test_development_only_is_rejected(self):
        with patch.object(release, 'run', return_value=DEV):
            with self.assertRaisesRegex(RuntimeError, 'Developer ID Application'):
                release.identity(None)

    def test_explicit_development_identity_is_rejected(self):
        with patch.object(release, 'run', return_value=DEV + DIST):
            with self.assertRaises(RuntimeError):
                release.identity('A' * 40)

    def test_distribution_selected_among_development_identities(self):
        with patch.object(release, 'run', return_value=DEV + DIST):
            self.assertEqual(release.identity(None)[0], 'B' * 40)

    def test_ambiguous_distribution_identity_requires_selection(self):
        second = DIST.replace('B' * 40, 'C' * 40).replace('Test', 'Other')
        with patch.object(release, 'run', return_value=DIST + second):
            with self.assertRaises(RuntimeError):
                release.identity(None)
            self.assertEqual(release.identity('C' * 40)[0], 'C' * 40)

    def test_no_output_before_apple_acceptance(self):
        for status in ['In Progress', 'Invalid', 'Rejected', None]:
            with self.subTest(status=status), tempfile.TemporaryDirectory() as temp:
                args = argparse.Namespace(work=Path(temp), profile='profile')
                with patch.object(release, 'run', return_value=json.dumps({'status': status})) as run:
                    with self.assertRaisesRegex(RuntimeError, '최종 ZIP'):
                        release.finish(args, {'submission_id': 'id'})
                self.assertEqual(run.call_count, 1)
                self.assertEqual(list(args.work.glob('*.zip')), [])

    def test_stapling_failure_stops_packaging(self):
        with tempfile.TemporaryDirectory() as temp:
            args = argparse.Namespace(work=Path(temp), profile='profile')
            with patch.object(release, 'run', side_effect=[json.dumps({'status':'Accepted'}), RuntimeError('staple failed')]):
                with self.assertRaisesRegex(RuntimeError, 'staple failed'):
                    release.finish(args, {'submission_id':'id'})
            self.assertEqual(list(args.work.glob('*.zip')), [])

    def test_gatekeeper_requires_notarized_result(self):
        with patch.object(release, 'signature'), patch.object(release, 'run', side_effect=['', 'source=Developer ID']):
            with self.assertRaisesRegex(RuntimeError, 'Notarized Developer ID'):
                release.assess(Path('/test.app'), 'TEAM')

    def test_modified_archive_never_uploaded(self):
        with tempfile.TemporaryDirectory() as temp:
            args = argparse.Namespace(work=Path(temp), profile='profile')
            (args.work / 'submission.zip').write_bytes(b'changed')
            with patch.object(release, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, '변경'):
                    release.submit(args, {'status':'prepared', 'submission_sha256':'old'})
                run.assert_not_called()

    def test_duplicate_or_uncertain_submission_never_retried(self):
        for state in [{'status':'submitted','submission_id':'id'}, {'status':'submitting'}]:
            with patch.object(release, 'run') as run:
                with self.assertRaisesRegex(RuntimeError, '중복'):
                    release.submit(argparse.Namespace(), state)
                run.assert_not_called()

    def test_upload_failure_preserves_uncertain_state(self):
        with tempfile.TemporaryDirectory() as temp:
            args = argparse.Namespace(work=Path(temp), profile='profile')
            upload = args.work / 'submission.zip'
            upload.write_bytes(b'archive')
            state = {'status':'prepared','submission_sha256':release.sha(upload)}
            with patch.object(release, 'run', side_effect=RuntimeError('connection lost')):
                with self.assertRaises(RuntimeError):
                    release.submit(args, state)
            self.assertEqual(json.loads((args.work / 'state.json').read_text())['status'], 'submitting')


if __name__ == '__main__':
    unittest.main(verbosity=2)
