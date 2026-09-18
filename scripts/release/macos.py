#!/usr/bin/env python3
"""Prepare, submit and verify a notarized release without touching the local app.

Only a Keychain profile name is accepted; never pass credentials in this script.
Apple processing is asynchronous. finish can be retried with the same submission.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed ({result.returncode}):\n{result.stdout}{result.stderr}')
    return result.stdout + result.stderr


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def save(path, data):
    pending = path.with_suffix('.tmp')
    pending.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    pending.replace(path)


def identity(requested):
    output = run('security', 'find-identity', '-v', '-p', 'codesigning')
    valid = re.findall(r'\)\s+([0-9A-F]{40})\s+"(Developer ID Application:[^"]+)"', output)
    if requested:
        valid = [(key, name) for key, name in valid if requested in (key, name)]
    if len(valid) != 1:
        raise RuntimeError('유효한 Developer ID Application 인증서를 하나 지정해야 합니다. 개발용 서명으로 대체하지 않습니다.')
    return valid[0]


def signature(app, team):
    run('codesign', '--verify', '--deep', '--strict', app)
    for target in (app, app / 'Contents/MacOS/clonie-mcp'):
        details = run('codesign', '-dv', '--verbose=4', target)
        if ('Authority=Developer ID Application:' not in details
                or f'TeamIdentifier={team}\n' not in details
                or 'runtime' not in details or 'Timestamp=' not in details):
            raise RuntimeError(f'배포 서명·팀·Hardened Runtime·타임스탬프 확인 실패: {target}')
    entitlements = run('codesign', '-d', '--entitlements', ':-', app)
    start = entitlements.find('<?xml')
    end = entitlements.find('</plist>')
    if start < 0 or end < 0:
        raise RuntimeError('앱 entitlement를 읽지 못했습니다.')
    values = plistlib.loads(entitlements[start:end + len('</plist>')].encode())
    if values != {'com.apple.security.device.audio-input': True}:
        raise RuntimeError('배포 앱의 최소 마이크 entitlement와 일치하지 않습니다.')


def prepare(args):
    key, name = identity(args.identity)
    source = args.app.resolve()
    if source == args.work or source in args.work.parents:
        raise RuntimeError('작업 폴더는 원본 앱 밖에 있어야 합니다.')
    info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.local.clonie' or info.get('CFBundleExecutable') != 'Clonie':
        raise RuntimeError('정식 Clonie.app만 배포할 수 있습니다.')
    if info.get('CFBundlePackageType') != 'APPL':
        raise RuntimeError('CFBundlePackageType=APPL이 필요합니다. 앱 번들을 다시 빌드하세요.')
    if not (source / 'Contents/Resources/EmbeddingModel/manifest.json').is_file():
        raise RuntimeError('모델을 동봉한 앱이 필요합니다: build.sh --app-only --include-model')
    # Refuse accidental reuse, including after an interrupted prepare.
    args.work.mkdir(parents=True, exist_ok=False)
    app = args.work / 'Clonie.app'
    run('ditto', source, app)
    entitlements = args.work / 'release.entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({'com.apple.security.device.audio-input': True}))
    # Sign inside out. No --deep signing: each shipped executable is explicit.
    run('codesign', '--force', '--sign', key, '--options', 'runtime', '--timestamp',
        app / 'Contents/MacOS/clonie-mcp')
    run('codesign', '--force', '--sign', key, '--options', 'runtime', '--timestamp',
        '--entitlements', entitlements, app)
    team = name.rsplit('(', 1)[1].rstrip(')')
    signature(app, team)
    upload = args.work / 'submission.zip'
    run('ditto', '-c', '-k', '--keepParent', app, upload)
    state = {'version': info['CFBundleShortVersionString'], 'team': team,
             'identity': name, 'submission_sha256': sha(upload), 'status': 'prepared'}
    save(args.work / 'state.json', state)
    print('배포 서명 준비 완료. submit으로 Apple 공증을 요청하세요.')


def submit(args, state):
    if state.get('submission_id') or state['status'] != 'prepared':
        raise RuntimeError('중복 제출하지 않습니다. 기존 submission ID로 finish를 사용하세요.')
    upload = args.work / 'submission.zip'
    if sha(upload) != state['submission_sha256']:
        raise RuntimeError('준비한 ZIP이 변경되었습니다.')
    # Do not automatically retry an ambiguous upload; reconcile Apple history first.
    state['status'] = 'submitting'
    save(args.work / 'state.json', state)
    result = json.loads(run('xcrun', 'notarytool', 'submit', upload,
                            '--keychain-profile', args.profile, '--output-format', 'json', '--no-wait'))
    save(args.work / 'submission-response.json', result)
    state.update(status='submitted', submission_id=result['id'])
    save(args.work / 'state.json', state)
    print(f"Apple 제출 완료: {result['id']}. finish로 결과를 확인하세요.")


def assess(app, team):
    signature(app, team)
    run('xcrun', 'stapler', 'validate', app)
    policy = run('spctl', '--assess', '--type', 'execute', '--verbose=4', app)
    if 'source=Notarized Developer ID' not in policy:
        raise RuntimeError('Notarized Developer ID 판정을 받지 못했습니다.')
    run('syspolicy_check', 'distribution', app)


def finish(args, state):
    if not state.get('submission_id'):
        raise RuntimeError('제출 ID가 없습니다. 불확실한 업로드는 Apple history에서 먼저 대조하세요.')
    result = json.loads(run('xcrun', 'notarytool', 'info', state['submission_id'],
                            '--keychain-profile', args.profile, '--output-format', 'json'))
    save(args.work / 'notary-status.json', result)
    if result.get('status') != 'Accepted':
        raise RuntimeError(f"Apple 공증 상태: {result.get('status')}. 최종 ZIP을 만들지 않습니다.")
    app = args.work / 'Clonie.app'
    run('xcrun', 'stapler', 'staple', app)
    assess(app, state['team'])
    archive = args.work / f"Clonie-{state['version']}-arm64-notarized.zip"
    if archive.exists():
        raise RuntimeError('기존 최종 ZIP을 덮어쓰지 않습니다.')
    # A final filename and receipt appear only after extraction and policy checks.
    candidate = args.work / 'verified-candidate.zip'
    if candidate.exists():
        raise RuntimeError('이전 candidate ZIP이 있습니다. 실패 원인을 먼저 확인하세요.')
    run('ditto', '-c', '-k', '--keepParent', app, candidate)
    with tempfile.TemporaryDirectory(prefix='clonie-release-verify-') as temp:
        run('ditto', '-x', '-k', candidate, temp)
        assess(Path(temp) / 'Clonie.app', state['team'])
    candidate.rename(archive)
    state.update(status='verified', archive=archive.name, sha256=sha(archive), bytes=archive.stat().st_size)
    save(args.work / 'state.json', state)
    print(json.dumps(state, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'submit', 'finish'])
    parser.add_argument('--work', required=True, type=Path, help='새 배포별 전용 작업 폴더')
    parser.add_argument('--app', type=Path, default=Path('Clonie.app'))
    parser.add_argument('--identity', default=os.environ.get('CLONIE_RELEASE_SIGN_ID'))
    parser.add_argument('--profile', default='clonie-notary', help='Keychain에 저장된 notarytool 프로필 이름')
    args = parser.parse_args()
    args.work = args.work.resolve()
    try:
        if args.action == 'prepare':
            prepare(args)
        else:
            state = json.loads((args.work / 'state.json').read_text())
            {'submit': submit, 'finish': finish}[args.action](args, state)
    except (RuntimeError, OSError, ValueError, KeyError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
