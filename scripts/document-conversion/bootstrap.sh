#!/bin/bash
# First-use installation only. No document paths are accepted by this script.
set -euo pipefail
ROOT="$1"
RESOURCES="$2"
MODE="${3:-prepare}"
[[ "$(/usr/bin/uname -m)" == "arm64" ]] || { echo 'This converter requires Apple silicon.' >&2; exit 1; }
mkdir -p "$ROOT"
child=''
lock="$ROOT/install.lock"
guard_file="$ROOT/.install-guard.pid"
owns_lock=false
cleanup() {
    if [[ -n "$child" ]]; then kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi
    if $owns_lock; then
        rm -f "$lock/pid" 2>/dev/null || true
        rmdir "$lock" 2>/dev/null || true
    fi
    rm -f "$guard_file" 2>/dev/null || true
}
# shlock uses an atomic link and checks the owning PID. Serialize stale-directory
# recovery too: two retrying apps must not remove a newly acquired install.lock.
if ! /usr/bin/shlock -p "$$" -f "$guard_file"; then
    echo 'Another converter installation is in progress.' >&2; exit 1
fi
trap cleanup EXIT
trap 'exit 130' INT TERM
# Keep the directory compatible with older installers. A pid-less directory can
# be an installer between mkdir and its PID write; give that window 30 seconds.
if ! mkdir "$lock" 2>/dev/null; then
    owner="$(cat "$lock/pid" 2>/dev/null || true)"
    stale=false
    if [[ "$owner" =~ ^[1-9][0-9]*$ ]]; then
        if ! kill -0 "$owner" 2>/dev/null; then stale=true; fi
    else
        modified="$(/usr/bin/stat -f %m "$lock")"
        now="$(/bin/date +%s)"
        if (( now - modified >= 30 )); then stale=true; fi
    fi
    if $stale; then
        rm -f "$lock/pid"; rmdir "$lock"; mkdir "$lock"
    else echo 'Another converter installation is in progress.' >&2; exit 1; fi
fi
owns_lock=true
echo "$$" > "$lock/pid"
run() {
    local status=0
    "$@" & child=$!
    wait "$child" || status=$?
    child=''
    return "$status"
}
VERSION="$(/usr/bin/shasum -a 256 "$RESOURCES/requirements.lock" "$RESOURCES/convert.py" "$RESOURCES/bootstrap.sh" | /usr/bin/cut -d ' ' -f 1 | /usr/bin/shasum -a 256 | /usr/bin/cut -d ' ' -f 1)"
export HF_HOME="$ROOT/hf" DOCLING_CACHE_DIR="$ROOT/cache"
export HF_HUB_DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 ANONYMIZED_TELEMETRY=False
export PIP_DISABLE_PIP_VERSION_CHECK=1 PYTHONNOUSERSITE=1 TOKENIZERS_PARALLELISM=false
# Run every cache check offline. Importing the conversion dependencies catches missing
# or broken libraries; model files use stat metadata, hashing only changed files.
VALIDATION_PY="$(cat <<'PY'
from pathlib import Path
import hashlib, importlib, json, os, sys
root = Path(sys.argv[1]).resolve()
mode = sys.argv[2]
deep = len(sys.argv) > 3 and sys.argv[3] == '--deep'
os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', HF_HUB_DISABLE_TELEMETRY='1')
required = (
    'docling-project--docling-layout-heron/config.json',
    'docling-project--docling-layout-heron/preprocessor_config.json',
    'docling-project--docling-layout-heron/model.safetensors',
    'docling-project--docling-models/model_artifacts/tableformer/accurate/tm_config.json',
    'docling-project--docling-models/model_artifacts/tableformer/accurate/tableformer_accurate.safetensors',
)
manifest_path = root / 'runtime-manifest.json'
def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()
def model_file(name):
    path = root / 'models' / name
    if not path.is_file() or not path.resolve().is_relative_to((root / 'models').resolve()):
        raise RuntimeError('Required model file is missing: ' + name)
    if path.stat().st_size == 0:
        raise RuntimeError('Required model file is empty: ' + name)
    return path
try:
    if mode == 'python':
        import ssl, ctypes, ensurepip
        import pip._internal.cli.main
        raise SystemExit(0)
    if mode in ('check', 'imports', 'manifest'):
        for name in ('docling.document_converter', 'docling_core.types.doc', 'docling_parse',
                     'docling.models.stages.layout.layout_model',
                     'docling.models.stages.table_structure.table_structure_model',
                     'docling_ibm_models.tableformer.data_management.tf_predictor', 'ocrmac.ocrmac', 'cv2', 'docx'):
            importlib.import_module(name)
    if mode == 'imports':
        raise SystemExit(0)
    if mode == 'manifest':
        files = {}
        for name in required:
            path = model_file(name)
            stat = path.stat()
            files[name] = dict(size=stat.st_size, mtime_ns=stat.st_mtime_ns, sha256=digest(path))
        temporary = manifest_path.with_suffix('.tmp')
        temporary.write_text(json.dumps(dict(version=1, files=files)), encoding='utf-8')
        temporary.replace(manifest_path)
    else:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        if manifest.get('version') != 1 or set(manifest['files']) != set(required):
            raise RuntimeError('Runtime manifest is incomplete')
        for name, expected in manifest['files'].items():
            path = model_file(name)
            stat = path.stat()
            if stat.st_size != expected['size']:
                raise RuntimeError('Model file size changed: ' + name)
            if (deep or stat.st_mtime_ns != expected['mtime_ns']) and digest(path) != expected['sha256']:
                raise RuntimeError('Model file contents changed: ' + name)
except Exception as error:
    print('Runtime cache check failed:', error, file=sys.stderr)
    raise SystemExit(40)
PY
)"
probe() {
    run /usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' \
        "$ROOT/python/bin/python3" -I -c "$VALIDATION_PY" "$ROOT" "$1" "$MODE"
}
same_version=false
if [[ -f "$ROOT/ready" && "$(cat "$ROOT/ready")" == "$VERSION" ]]; then same_version=true; fi
if [[ -x "$ROOT/python/bin/python3" ]] && $same_version && probe check; then
    exit 0
fi
# A stale ready marker must not survive a failed repair or make the next retry skip it.
rm -f "$ROOT/ready"
if [[ "$MODE" == "--check" ]]; then exit 1; fi
preserve() {
    if [[ -e "$1" || -L "$1" ]]; then
        local backup
        backup="$(/usr/bin/mktemp -d "$ROOT/recovered.XXXXXX")"
        mv "$1" "$backup/"
        echo "Preserved previous runtime files in $backup"
    fi
}
if [[ ! -x "$ROOT/python/bin/python3" ]] || ! probe python; then
    preserve "$ROOT/python"
    archive="$ROOT/python.tar.gz"
    run /usr/bin/curl --fail --location --retry 2 --connect-timeout 30 --max-time 900 \
        'https://github.com/astral-sh/python-build-standalone/releases/download/20240909/cpython-3.12.6%2B20240909-aarch64-apple-darwin-install_only.tar.gz' -o "$archive"
    echo "899f46eb592fcac4e834c064e4c901e8a4a6b5864e80b18efd2f0b7c3c050584  $archive" | /usr/bin/shasum -a 256 -c -
    mkdir -p "$ROOT/unpack"
    run /usr/bin/tar -xzf "$archive" -C "$ROOT/unpack"
    mv "$ROOT/unpack/python" "$ROOT/python"
    rmdir "$ROOT/unpack"
    rm "$archive"
fi
# Fully pinned transitive set from the Korean OCR/table probe. Binary wheels only:
# installation must never unexpectedly require a compiler or developer Python.
pip_args=(install --only-binary=:all: --no-deps --requirement "$RESOURCES/requirements.lock")
needs_packages=false
if ! $same_version; then needs_packages=true; fi
if [[ -f "$ROOT/repair-dependencies" ]] || ! probe imports; then
    # Remember an interrupted repair too: pip may otherwise accept partial .dist-info.
    touch "$ROOT/repair-dependencies"
    pip_args+=(--force-reinstall)
    needs_packages=true
fi
if $needs_packages; then
    run "$ROOT/python/bin/python3" -I -m ensurepip
    run "$ROOT/python/bin/python3" -I -m pip "${pip_args[@]}"
fi
if ! probe models; then
    # Keep old model cards/licenses. Moving the local snapshot also prevents HF's
    # existing-file shortcut from accepting a damaged file during re-download.
    preserve "$ROOT/models"
fi
run "$ROOT/python/bin/python3" -I "$RESOURCES/convert.py" prepare "$ROOT"
probe manifest
rm -f "$ROOT/repair-dependencies"
echo "$VERSION" > "$ROOT/ready.tmp"
mv "$ROOT/ready.tmp" "$ROOT/ready"
