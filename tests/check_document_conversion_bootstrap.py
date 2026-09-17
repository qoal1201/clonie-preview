"""Exercise bootstrap locking with fake local Python; never download or build."""
from concurrent.futures import ThreadPoolExecutor
import ast
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import shlex
import tarfile
import tempfile
import time
import unittest
import sys

RESOURCES = Path(__file__).resolve().parents[1] / "scripts/document-conversion"
BOOTSTRAP = RESOURCES / "bootstrap.sh"


class BootstrapLocks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="clonie-bootstrap-lock-")
        self.root = Path(self.temporary.name)
        self.python = self.root / "python/bin/python3"
        self.python.parent.mkdir(parents=True)
        self.python.write_text('#!/bin/bash\nif [[ "$2" != "-c" ]]; then touch "$(dirname "$0")/invoked"; fi\nexit 0\n')
        self.python.chmod(0o700)
        digests = "".join(hashlib.sha256((RESOURCES / name).read_bytes()).hexdigest() + "\n"
                          for name in ("requirements.lock", "convert.py", "bootstrap.sh"))
        (self.root / "ready").write_text(hashlib.sha256(digests.encode()).hexdigest() + "\n")
        self.command = ["/bin/bash", str(BOOTSTRAP), str(self.root), str(RESOURCES)]
        self.lock = self.root / "install.lock"

    def tearDown(self):
        self.temporary.cleanup()

    def run_bootstrap(self, **kwargs):
        return subprocess.run(self.command, capture_output=True, text=True, timeout=5, **kwargs)

    def assert_clean(self):
        self.assertFalse(self.lock.exists())
        self.assertFalse((self.root / ".install-guard.pid").exists())

    def test_ready_and_resource_relocation(self):
        self.assertEqual(self.run_bootstrap().returncode, 0)
        moved = self.root / "relocated resources"
        moved.mkdir()
        for name in ("requirements.lock", "convert.py", "bootstrap.sh"):
            (moved / name).write_bytes((RESOURCES / name).read_bytes())
        result = subprocess.run(["/bin/bash", str(moved / "bootstrap.sh"), str(self.root), str(moved)],
                                capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertFalse((self.python.parent / "invoked").exists(), "Moving resources must not rerun installation")
        self.assert_clean()

    def test_recent_pidless_lock_is_preserved(self):
        self.lock.mkdir()
        self.assertNotEqual(self.run_bootstrap().returncode, 0)
        self.assertTrue(self.lock.is_dir())

    def test_stale_pidless_lock_recovers(self):
        self.lock.mkdir()
        os.utime(self.lock, (time.time() - 31, time.time() - 31))
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assert_clean()

    def test_live_owner_is_preserved_even_when_old(self):
        self.lock.mkdir()
        (self.lock / "pid").write_text(str(os.getpid()))
        os.utime(self.lock, (time.time() - 60, time.time() - 60))
        self.assertNotEqual(self.run_bootstrap().returncode, 0)
        self.assertEqual((self.lock / "pid").read_text(), str(os.getpid()))

    def test_dead_owner_recovers(self):
        self.lock.mkdir()
        (self.lock / "pid").write_text("99999999")
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assert_clean()

    def test_pid_write_failure_cleans_both_locks(self):
        # A failing echo after shell redirection reproduces an unsuccessful PID
        # write without filling the disk or changing the production script.
        injection = self.root / "fail-echo.sh"
        injection.write_text('echo() { if [[ "$#" == 1 && "$1" =~ ^[0-9]+$ ]]; then return 73; fi; builtin echo "$@"; }\n')
        result = self.run_bootstrap(env={**os.environ, "BASH_ENV": str(injection)})
        self.assertEqual(result.returncode, 73)
        self.assert_clean()

    def test_preparation_failure_is_retryable(self):
        (self.root / "ready").unlink()
        self.python.write_text('#!/bin/bash\nif [[ "$*" == *"-m pip"* ]]; then exit 74; fi\nexit 0\n')
        self.assertEqual(self.run_bootstrap().returncode, 74)
        self.assertFalse((self.root / "ready").exists())
        self.assert_clean()
        self.python.write_text("#!/bin/bash\nexit 0\n")
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assertTrue((self.root / "ready").exists())
        self.assert_clean()

    def test_simultaneous_stale_recovery_has_one_installer(self):
        (self.root / "ready").unlink()
        self.lock.mkdir()
        os.utime(self.lock, (time.time() - 31, time.time() - 31))
        self.python.write_text('#!/bin/bash\nif [[ "$*" == *"-m pip"* ]]; then /bin/sleep 1; fi\nexit 0\n')
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.run_bootstrap(), range(4)))
        self.assertEqual(sum(result.returncode == 0 for result in results), 1)
        self.assert_clean()

    def test_cancel_and_concurrent_retries(self):
        (self.root / "ready").unlink()
        self.python.write_text('#!/bin/bash\ntouch "$(dirname "$0")/started"\nexec /bin/sleep 30\n')
        process = subprocess.Popen(self.command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not (self.python.parent / "started").exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue((self.python.parent / "started").exists())
            with ThreadPoolExecutor(max_workers=4) as pool:
                results = list(pool.map(lambda _: self.run_bootstrap(), range(4)))
            self.assertTrue(all(result.returncode != 0 for result in results))
            self.assertEqual((self.lock / "pid").read_text().strip(), str(process.pid))
            process.terminate()
            process.communicate(timeout=5)
            self.assertEqual(process.returncode, 130)
            self.assert_clean()
        finally:
            if process.poll() is None:
                process.terminate()
                process.communicate(timeout=5)


class RuntimeCacheRecovery(unittest.TestCase):
    """Real offline validator, tiny fake imports/models, and simulated installers."""
    def setUp(self):
        BootstrapLocks.setUp(self)
        self.validation = BOOTSTRAP.read_text().split('VALIDATION_PY="$(cat <<\'PY\'\n', 1)[1].split('\nPY\n)"', 1)[0]
        tree = ast.parse(self.validation)
        required = next(ast.literal_eval(node.value) for node in tree.body
                        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'required' for t in node.targets))
        imports = next(ast.literal_eval(node.iter) for node in ast.walk(tree)
                       if isinstance(node, ast.For) and isinstance(node.target, ast.Name)
                       and node.target.id == 'name' and isinstance(node.iter, ast.Tuple))
        self.modules = self.root / "fixture-modules"
        sources = {}
        for module in (*imports, "pip._internal.cli.main"):
            parts = module.split('.')
            for depth in range(1, len(parts)):
                sources[str(Path(*parts[:depth]) / '__init__.py')] = '# fixture package\n'
            sources[str(Path(*parts[:-1]) / (parts[-1] + '.py'))] = 'value = 1\n'
        models = {name: 'model fixture: ' + name for name in required}
        models['docling-project--docling-models/README.md'] = 'license: cdla-permissive-2.0\n'
        spec = dict(modules_root=str(self.modules), modules=sources, models=models)
        self.spec = self.root / 'fixture-spec.json'
        self.spec.write_text(json.dumps(spec))
        for relative, content in sources.items():
            path = self.modules / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        for relative, content in models.items():
            path = self.root / 'models' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.python.write_text(f'''#!{sys.executable}
import json, pathlib, sys
root = pathlib.Path({str(self.root)!r})
spec = json.loads(pathlib.Path({str(self.spec)!r}).read_text())
args = sys.argv[1:]
with (root / 'calls').open('a') as out:
    out.write(('probe:' + args[4] if args[:2] == ['-I', '-c'] else ' '.join(args)) + '\\n')
if args[:2] == ['-I', '-c']:
    sys.path.insert(0, spec['modules_root'])
    sys.argv = ['validator', *args[3:]]
    exec(args[2])
elif args[:3] == ['-I', '-m', 'pip']:
    if (root / 'fail-pip').exists(): raise SystemExit(75)
    for name, content in spec['modules'].items():
        path = pathlib.Path(spec['modules_root']) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
elif len(args) > 2 and args[2] == 'prepare':
    for name, content in spec['models'].items():
        path = root / 'models' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
''')
        self.required = required
        result = self.validate('manifest')
        self.assertEqual(result.returncode, 0, result.stderr)
        (self.root / 'calls').write_text('')

    tearDown = BootstrapLocks.tearDown
    run_bootstrap = BootstrapLocks.run_bootstrap
    assert_clean = BootstrapLocks.assert_clean

    def validate(self, mode):
        return subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                               str(self.python), '-I', '-c', self.validation, str(self.root), mode],
                              capture_output=True, text=True, timeout=5)

    def test_healthy_cache_checks_without_installation(self):
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['probe:check'])

    def test_missing_model_repairs_and_preserves_model_notices(self):
        (self.root / 'models' / self.required[0]).unlink()
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / 'calls').read_text()
        self.assertNotIn('-m pip', calls, 'Healthy packages must not be reinstalled for a missing model')
        self.assertIn(' prepare ', calls)
        notices = list(self.root.glob('recovered.*/models/docling-project--docling-models/README.md'))
        self.assertEqual(len(notices), 1)
        self.assertIn('cdla-permissive', notices[0].read_text())
        self.assertEqual(self.validate('check').returncode, 0)

    def test_same_size_model_damage_is_detected(self):
        path = self.root / 'models' / self.required[0]
        path.write_bytes(b'X' * path.stat().st_size)
        os.utime(path, ns=(time.time_ns(), time.time_ns() + 1_000_000_000))
        self.assertNotEqual(self.validate('check').returncode, 0)
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assertEqual(self.validate('check').returncode, 0)

    def test_retry_deep_check_detects_damage_with_unchanged_stat_metadata(self):
        path = self.root / 'models' / self.required[0]
        stat = path.stat()
        path.write_bytes(b'X' * stat.st_size)
        os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        result = subprocess.run([*self.command, '--deep'], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(' prepare ', (self.root / 'calls').read_text())
        self.assertEqual(self.validate('check').returncode, 0)

    def test_bad_document_retry_does_not_reinstall_healthy_runtime(self):
        result = subprocess.run([*self.command, '--deep'], capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['probe:check'])

    def test_missing_import_forces_pinned_reinstall_but_keeps_models(self):
        (self.modules / 'docling/document_converter.py').unlink()
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--force-reinstall', (self.root / 'calls').read_text())
        self.assertEqual(list(self.root.glob('recovered.*/models')), [])
        self.assertFalse((self.root / 'repair-dependencies').exists())
        self.assertEqual(self.validate('check').returncode, 0)

    def test_failed_dependency_repair_can_retry(self):
        (self.modules / 'docling/document_converter.py').unlink()
        (self.root / 'fail-pip').touch()
        self.assertEqual(self.run_bootstrap().returncode, 75)
        self.assertFalse((self.root / 'ready').exists())
        self.assertTrue((self.root / 'repair-dependencies').exists())
        self.assert_clean()
        (self.root / 'fail-pip').unlink()
        self.assertEqual(self.run_bootstrap().returncode, 0)
        self.assertEqual(self.validate('check').returncode, 0)

    def test_unusable_interpreter_invalidates_ready_without_network_in_check_mode(self):
        self.python.chmod(0o600)
        result = subprocess.run([*self.command, '--check'], capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'ready').exists())
        self.assert_clean()

    def test_interpreter_repair_preserves_old_license_and_installs_at_correct_path(self):
        archive = self.root / 'fixture-python.tar.gz'
        with tarfile.open(archive, 'w:gz') as output:
            for name, data, mode in (
                ('python/bin/python3', self.python.read_bytes(), 0o755),
                ('python/lib/python3.12/LICENSE.txt', b'new fixture interpreter notice', 0o644),
            ):
                info = tarfile.TarInfo(name); info.size = len(data); info.mode = mode
                output.addfile(info, io.BytesIO(data))
        previous = self.root / 'python/lib/python3.12/LICENSE.txt'
        previous.parent.mkdir(parents=True)
        previous.write_text('previous runtime license must remain')
        self.python.chmod(0o600)
        # Intercept the download/checksum commands only in this fixture shell.
        # The production URL and checksum are unchanged; no external request runs.
        injection = self.root / 'local-download.sh'
        injection.write_text(f'''
function /usr/bin/curl() {{ /bin/cp {shlex.quote(str(archive))} "${{!#}}"; }}
function /usr/bin/shasum() {{
  if [[ "$*" == '-a 256 -c -' ]]; then /bin/cat > {shlex.quote(str(self.root / 'checked-sha'))}; return 0; fi
  command /usr/bin/shasum "$@"
}}
''')
        result = self.run_bootstrap(env={**os.environ, 'BASH_ENV': str(injection)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.access(self.python, os.X_OK))
        self.assertFalse((self.root / 'python/python').exists(), 'Repair must not nest Python inside an old installation')
        self.assertEqual(previous.read_text(), 'new fixture interpreter notice')
        preserved = list(self.root.glob('recovered.*/python/lib/python3.12/LICENSE.txt'))
        self.assertEqual(len(preserved), 1)
        self.assertEqual(preserved[0].read_text(), 'previous runtime license must remain')
        self.assertTrue((self.root / 'checked-sha').read_text().startswith('899f46eb592fcac4e834c064e4c901e8a4a6b5864e80b18efd2f0b7c3c050584'))
        self.assertEqual(self.validate('check').returncode, 0)
        self.assert_clean()


if __name__ == "__main__":
    unittest.main()
