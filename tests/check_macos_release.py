"""Release safety checks use mocked Apple tools; they do not prove notarization."""
import argparse
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'scripts/release/macos.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
DEV = '  1) ' + 'A' * 40 + ' "Apple Development: Test (TEAM)"\n'
DIST = '  2) ' + 'B' * 40 + ' "Developer ID Application: Test (TEAM)"\n'


class BuildModelPreflightTests(unittest.TestCase):
    def assert_model_failure_preserves_existing_app(self, prepare_model, expected_error):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            shutil.copy2(Path(__file__).parents[1] / 'build.sh', root / 'build.sh')
            (root / 'build.sh').chmod(0o755)
            for directory in (
                'scripts/document-conversion',
                '.agents/skills/clonie-session-record',
                '.agents/skills/clonie',
                'ThirdPartyNotices',
            ):
                (root / directory).mkdir(parents=True)
            (root / 'LICENSE').write_text('license fixture', encoding='utf-8')
            (root / 'LICENSING.md').write_text('notices fixture', encoding='utf-8')

            existing = root / 'Clonie.app'
            fixtures = {
                'Contents/MacOS/Clonie': b'existing executable',
                'Contents/Info.plist': b'existing plist',
                'Contents/_CodeSignature/CodeResources': b'existing signature',
            }
            for relative, content in fixtures.items():
                path = existing / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)

            # The stub would make the rest of the old build path runnable. A model
            # preflight failure must happen before it is invoked or the app is touched.
            commands = root / 'commands'
            commands.mkdir()
            swift_log = root / 'swift.log'
            swift = commands / 'swift'
            swift.write_text('''#!/bin/bash
set -euo pipefail
printf '%s\\n' "$*" >> "$BUILD_SWIFT_LOG"
mkdir -p .build/release
case " $* " in
  *" --product Clonie "*) printf old > .build/release/Clonie; chmod +x .build/release/Clonie ;;
  *" --product clonie-mcp "*) printf old > .build/release/clonie-mcp; chmod +x .build/release/clonie-mcp ;;
esac
''', encoding='utf-8')
            swift.chmod(0o755)

            model = root / 'model'
            prepare_model(model)
            temp_root = root / 'tmp'
            temp_root.mkdir()
            env = {
                **os.environ,
                'PATH': f'{commands}:{os.environ["PATH"]}',
                'CLONIE_SIGN_ID': 'TEST-SIGNING-IDENTITY',
                'CLONIE_MODEL_DIR': str(model),
                'BUILD_SWIFT_LOG': str(swift_log),
                'TMPDIR': str(temp_root),
            }
            result = subprocess.run(
                [str(root / 'build.sh'), '--app-only', '--include-model'],
                cwd=root, env=env, capture_output=True, text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(expected_error, result.stderr)
            self.assertNotIn('Building Clonie targets', result.stdout)
            self.assertFalse(swift_log.exists())
            actual = {
                relative: ((existing / relative).read_bytes() if (existing / relative).is_file() else None)
                for relative in fixtures
            }
            self.assertEqual(actual, fixtures)
            self.assertEqual(list(temp_root.iterdir()), [])

    def test_missing_model_fails_before_replacing_existing_app(self):
        self.assert_model_failure_preserves_existing_app(
            lambda model: None,
            '모델 디렉터리가 없거나 심볼릭 링크다',
        )

    def test_invalid_manifest_fails_before_replacing_existing_app(self):
        def invalid_manifest(model):
            model.mkdir()
            (model / 'manifest.json').write_text('{', encoding='utf-8')

        self.assert_model_failure_preserves_existing_app(
            invalid_manifest,
            'manifest.json을 읽지 못한다',
        )


class ReleaseTests(unittest.TestCase):
    def product_fixture(self, root):
        app = root / 'Clonie.app'
        package = app / 'Contents/Resources/CloniePlugin'
        repo = Path(__file__).parents[1]
        shutil.copytree(repo / 'plugins/clonie', package / 'plugins/clonie')
        for name in ['.agents/plugins/marketplace.json', '.claude-plugin/marketplace.json']:
            target = package / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repo / name, target)
        shutil.copy2(repo / 'scripts/install-clonie-plugin.sh', package / 'install.sh')
        shutil.copy2(repo / 'plugins/clonie/README.md', package / 'README.md')
        model = app / 'Contents/Resources/EmbeddingModel'
        model.mkdir()
        (model / 'manifest.json').write_text('{}')
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.local.clonie', 'CFBundleExecutable': 'Clonie',
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.1.0',
        }))
        return app, package

    def test_product_check_records_host_versions_and_packaged_files(self):
        with tempfile.TemporaryDirectory() as temp:
            app, package = self.product_fixture(Path(temp))
            response = subprocess.CompletedProcess([], 0, 'proposal-v1\n', '')
            with patch.object(release.subprocess, 'run', return_value=response) as run:
                result = release.product_contract(app)
            self.assertEqual(result['write_contract'], 'proposal-v1')
            self.assertEqual(set(result['plugin_versions']), {'codex', 'claude'})
            self.assertEqual(result['package_files']['install.sh'], release.sha(package / 'install.sh'))
            self.assertEqual(run.call_args.args[0], [str(app / 'Contents/MacOS/clonie-mcp'), '--write-contract'])
            self.assertEqual(run.call_args.kwargs['timeout'], 10)

    def test_incomplete_or_misdirected_plugin_never_reaches_signing(self):
        for defect in ['missing_launcher', 'wrong_marketplace', 'wrong_mcp', 'outside_package']:
            with self.subTest(defect=defect), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                app, package = self.product_fixture(root)
                launcher = package / 'plugins/clonie/scripts/start-mcp.sh'
                if defect == 'missing_launcher':
                    launcher.unlink()
                elif defect == 'wrong_marketplace':
                    path = package / '.agents/plugins/marketplace.json'
                    value = json.loads(path.read_text())
                    value['plugins'][0]['source']['path'] = '/a/developer/checkout'
                    path.write_text(json.dumps(value))
                elif defect == 'wrong_mcp':
                    path = package / 'plugins/clonie/.mcp.json'
                    path.write_text('{"mcpServers":{"clonie":{"command":"old-clonie"}}}')
                else:
                    external = root / 'external.sh'
                    external.write_text('external')
                    launcher.unlink()
                    launcher.symlink_to(external)
                args = argparse.Namespace(app=app, work=root / 'release', identity=None)
                with patch.object(release, 'identity', return_value=('key', 'name')), patch.object(release, 'run') as run:
                    with self.assertRaises(RuntimeError):
                        release.prepare(args)
                    run.assert_not_called()
                self.assertFalse(args.work.exists())

    def test_old_or_hung_mcp_never_reaches_signing(self):
        for response in [subprocess.CompletedProcess([], 0, 'immediate-write\n', ''),
                         subprocess.CompletedProcess([], 1, 'proposal-v1\n', ''),
                         subprocess.TimeoutExpired('clonie-mcp', 10)]:
            with self.subTest(response=response), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                app, _ = self.product_fixture(root)
                args = argparse.Namespace(app=app, work=root / 'release', identity=None)
                with patch.object(release, 'identity', return_value=('key', 'name')), \
                        patch.object(release, 'run') as run, \
                        patch.object(release.subprocess, 'run', **({'side_effect': response} if isinstance(response, Exception) else {'return_value': response})):
                    with self.assertRaises(RuntimeError):
                        release.prepare(args)
                    run.assert_not_called()
                self.assertFalse(args.work.exists())

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
