import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, cpSync, rmSync, readdirSync, symlinkSync, realpathSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';

const repo = resolve(import.meta.dirname, '..');

function fixture(t, host) {
  const root = mkdtempSync(join(tmpdir(), 'clonie-plugin-'));
  t.after(() => rmSync(root, {recursive:true, force:true}));
  const plugin = join(root, "설치된 플러그인 ' 복사본");
  cpSync(join(repo, 'plugins/clonie'), plugin, {recursive:true});
  const app = join(root, "한글 ' Clonie.app");
  const executable = join(app, 'Contents/MacOS');
  mkdirSync(executable, {recursive:true});
  writeFileSync(join(executable, 'clonie-mcp'), '#!/bin/bash\nif [[ "$1" == --write-contract ]]; then printf "proposal-v1\\n"; exit 0; fi\nprintf "%s\\n" "$1" "$2"\ncat\n', {mode:0o755});
  const vault = join(root, '저장소 $literal');
  mkdirSync(vault);
  const manifest = JSON.parse(readFileSync(join(plugin, '.codex-plugin/plugin.json')));
  const config = host === 'codex' ? manifest.mcpServers.clonie :
    JSON.parse(readFileSync(join(plugin, '.mcp.json'))).mcpServers.clonie;
  // Codex resolves cwd against its cache but does not expand Claude's argument macro.
  const args = host === 'codex' ? config.args :
    config.args.map(arg => arg.replaceAll('${CLAUDE_PLUGIN_ROOT}', plugin));
  const cwd = config.cwd ? resolve(plugin, config.cwd) : root;
  return {root, plugin, app, vault:realpathSync(vault), run(overrides={}, input='', extraArgs=[]) {
    const environment = {...process.env, CLONIE_APP_PATH:app, CLONIE_VAULT:vault, ...overrides};
    for(const key of Object.keys(environment))if(environment[key]===undefined)delete environment[key];
    const env = host === 'codex' ? Object.fromEntries(
      ['HOME', 'PATH', 'TMPDIR', ...(config.env_vars || [])]
        .filter(key => key in environment).map(key => [key, environment[key]])) : environment;
    return spawnSync(config.command, [...args, ...extraArgs], {cwd, encoding:'utf8', input, env});
  }};
}

for (const host of ['codex', 'claude']) {
test(`${host}: 캐시로 복사한 플러그인이 공백·한글 경로와 MCP 표준 입출력을 보존한다`, t => {
  const f = fixture(t, host);
  const message = '{"jsonrpc":"2.0","id":1,"method":"initialize"}\n';
  const r = f.run({}, message);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout, `--vault\n${f.vault}\n${message}`);
  assert.equal(r.stderr, '');
});

test(`${host}: 명시한 앱이 없으면 다른 설치판으로 조용히 연결하지 않는다`, t => {
  const f = fixture(t, host);
  const r = f.run({CLONIE_APP_PATH:join(f.root, '없는 앱.app')});
  assert.notEqual(r.status, 0);
  assert.equal(r.stdout, '');
  assert.match(r.stderr, /앱을 찾지 못했습니다/);
});

test(`${host}: 즉시 쓰는 옛 앱이나 알 수 없는 변경 방식을 가진 앱에는 자료를 보내지 않는다`, t => {
  const f = fixture(t, host), binary = join(f.app, 'Contents/MacOS/clonie-mcp');
  const marker = join(f.vault, 'server-was-started');
  for (const response of ['exit 2', 'printf "direct-write\\n"', 'printf "proposal-v1\\nextra\\n"']) {
    writeFileSync(binary, `#!/bin/bash\nif [[ "$1" == --write-contract ]]; then ${response}; exit; fi\nprintf started > "$2/server-was-started"\ncat\n`, {mode:0o755});
    for (const args of [[], ['--check']]) {
      const r = f.run({}, 'PRIVATE_MCP_REQUEST', args);
      assert.notEqual(r.status, 0);
      assert.equal(r.stdout, '');
      assert.match(r.stderr, /승인 방식을 지원하지 않습니다/);
      assert.deepEqual(readdirSync(f.vault), [], marker);
    }
  }
});

test(`${host}: 없는 저장소를 만들거나 기본 폴더로 대신 연결하지 않는다`, t => {
  const f = fixture(t, host);
  const before = readdirSync(f.root).sort();
  for (const vault of ['', '/', 'relative', '${user_config.vault}', join(f.root, '없는 저장소')]) {
    const r = f.run({CLONIE_VAULT:vault});
    assert.notEqual(r.status, 0, vault);
    assert.equal(r.stdout, '', vault);
    assert.match(r.stderr, /저장소 폴더를 찾지 못했습니다/);
  }
  assert.deepEqual(readdirSync(f.root).sort(), before);
});

test(`${host}: init 진단은 MCP를 실행하거나 자료를 읽지 않고 경로만 확인한다`, t => {
  const f=fixture(t,host);
  writeFileSync(join(f.vault,'개인 문서.md'),'DO_NOT_READ_PRIVATE_BODY');
  const r=f.run({},'not sent to MCP',['--check']);
  assert.equal(r.status,0,r.stderr);
  assert.match(r.stdout,/status=ready_to_start/);
  assert.match(r.stdout,/live_connection=unverified/);
  assert.match(r.stdout,/app_source=environment/);
  assert.match(r.stdout,/vault_source=environment/);
  assert.match(r.stdout,/write_contract=proposal-v1/);
  assert.doesNotMatch(r.stdout,/--vault|not sent to MCP|DO_NOT_READ_PRIVATE_BODY/);
});

test(`${host}: 루트의 별칭은 거절하고 선택 폴더의 별칭은 같은 실제 경로에 연결한다`, t => {
  const f=fixture(t,host),link=join(f.root,'저장소 별칭'),disk=join(f.root,'디스크 별칭');
  symlinkSync(f.vault,link);symlinkSync('/',disk);
  const good=f.run({CLONIE_VAULT:link});
  assert.equal(good.status,0,good.stderr);assert.equal(good.stdout,`--vault\n${f.vault}\n`);
  const bad=f.run({CLONIE_VAULT:disk});
  assert.notEqual(bad.status,0);assert.equal(bad.stdout,'');assert.match(bad.stderr,/디스크 루트/);
});

test(`${host}: 앱이 등록한 위치와 선택 폴더를 사용하며 없는 선택은 만들지 않는다`, t => {
  const f=fixture(t,host),quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
  // Substitute only the OS preference reader in the copied package. Never touch user defaults.
  const reader=join(f.root,'defaults-double'),resolver=join(f.plugin,'skills/clonie-init/scripts/connection.sh');
  writeFileSync(reader,`#!/bin/bash\ncase "$*" in\n 'read com.local.clonie mcpAppPath') printf '%s\\n' ${quote(f.app)};;\n 'read com.local.clonie vaultPath') printf '%s\\n' ${quote(f.vault)};;\n *) exit 1;;\nesac\n`,{mode:0o755});
  writeFileSync(resolver,readFileSync(resolver,'utf8').replaceAll('/usr/bin/defaults',quote(reader)));
  const r=f.run({CLONIE_APP_PATH:undefined,CLONIE_VAULT:undefined});
  assert.equal(r.status,0,r.stderr);assert.equal(r.stdout,`--vault\n${f.vault}\n`);
  writeFileSync(reader,'#!/bin/bash\nexit 1\n');
  const missing=f.run({CLONIE_VAULT:undefined});
  assert.notEqual(missing.status,0);assert.equal(missing.stdout,'');assert.match(missing.stderr,/연결한 저장소가 없습니다/);
  assert.deepEqual(readdirSync(f.vault),[]);
});
}

test('배포할 AI 지침과 라이선스가 정본에서 뒤처지지 않는다', () => {
  const r = spawnSync('python3', ['scripts/sync-clonie-plugin.py', '--check'], {cwd:repo, encoding:'utf8'});
  assert.equal(r.status, 0, r.stdout+r.stderr);
});

for(const host of ['codex','claude'])test(`${host}: 앱 동봉 패키지는 소스 없이 설치되며 등록 실패 뒤 설치하지 않는다`, t=>{
  const root=mkdtempSync(join(tmpdir(),'clonie-package-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const bundle=join(root,"Clonie ' 패키지"),bin=join(root,'bin'),log=join(root,'calls');
  const packed=spawnSync('python3',['scripts/package-clonie-plugin.py',bundle],{cwd:repo,encoding:'utf8'});
  assert.equal(packed.status,0,packed.stderr);
  const market=JSON.parse(readFileSync(join(bundle,'.agents/plugins/marketplace.json')));
  const plugin=resolve(bundle,market.plugins[0].source.path);
  assert.equal(JSON.parse(readFileSync(join(plugin,'.codex-plugin/plugin.json'))).name,'clonie');
  assert.match(readFileSync(join(plugin,'skills/clonie-init/SKILL.md'),'utf8'),/name: clonie-init/);
  mkdirSync(bin);
  const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
  const recorder=`#!/bin/bash\nprintf '%s\\n' "$@" >> ${quote(log)}\n`;
  writeFileSync(join(bin,host),recorder,{mode:0o755});
  const install=()=>spawnSync('/bin/bash',[join(bundle,'install.sh'),host],{
    cwd:root,encoding:'utf8',env:{...process.env,PATH:bin+':'+process.env.PATH}});
  const ok=install();assert.equal(ok.status,0,ok.stderr);
  assert.deepEqual(readFileSync(log,'utf8').trim().split('\n'),[
    'plugin','marketplace','add',realpathSync(bundle),'plugin',host==='codex'?'add':'install','clonie@clonie']);
  writeFileSync(log,'');writeFileSync(join(bin,host),recorder+'exit 17\n');
  const bad=install();assert.equal(bad.status,17);
  assert.deepEqual(readFileSync(log,'utf8').trim().split('\n'),['plugin','marketplace','add',realpathSync(bundle)]);
  assert.doesNotMatch(bad.stdout,/installation finished/);
  const again=spawnSync('python3',['scripts/package-clonie-plugin.py',bundle],{cwd:repo,encoding:'utf8'});
  assert.notEqual(again.status,0);assert.match(again.stderr,/already exists/);
});

function desktopInstaller(t) {
  const root=mkdtempSync(join(tmpdir(),'clonie-desktop-install-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const bundle=join(root,"Clonie ' 패키지"),apps=join(root,"설치 앱 ' 목록"),log=join(root,'calls');
  const packed=spawnSync('python3',['scripts/package-clonie-plugin.py',bundle],{cwd:repo,encoding:'utf8'});
  assert.equal(packed.status,0,packed.stderr);
  const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
  const installer=join(bundle,'install.sh'),source=readFileSync(installer,'utf8');
  // Substitute the OS app locations only; never install through the user's real desktop app.
  const locations='for clonie_apps in /Applications "$HOME/Applications"';
  assert.ok(source.includes(locations));
  writeFileSync(installer,source.replace(locations,`for clonie_apps in ${quote(apps)}`));
  const binary=join(apps,'ChatGPT.app/Contents/Resources/codex-cli/bin/codex');
  mkdirSync(resolve(binary,'..'),{recursive:true});
  const recorder=`#!/bin/bash\nprintf '%s\\n' "$@" >> ${quote(log)}\n`;
  return {root,bundle,binary,log,recorder,install(path='/usr/bin:/bin') {
    return spawnSync('/bin/bash',[installer,'codex'],{
      cwd:root,encoding:'utf8',env:{...process.env,PATH:path}});
  }};
}

test('Codex: CLI가 PATH에 없는 데스크톱 설치에서도 앱 동봉 실행 파일로 설치한다',t=>{
  const f=desktopInstaller(t);
  writeFileSync(f.binary,f.recorder,{mode:0o755});
  const result=f.install();assert.equal(result.status,0,result.stderr);
  assert.deepEqual(readFileSync(f.log,'utf8').trim().split('\n'),[
    'plugin','marketplace','add',realpathSync(f.bundle),'plugin','add','clonie@clonie']);
  writeFileSync(f.log,'');writeFileSync(f.binary,f.recorder+'exit 17\n');
  const failed=f.install();assert.equal(failed.status,17);
  assert.deepEqual(readFileSync(f.log,'utf8').trim().split('\n'),[
    'plugin','marketplace','add',realpathSync(f.bundle)]);
  assert.doesNotMatch(failed.stdout,/installation finished/);
});

test('Codex: 사용자가 PATH에 둔 CLI가 있으면 데스크톱의 다른 실행 파일로 바꾸지 않는다',t=>{
  const f=desktopInstaller(t),bin=join(f.root,'bin');mkdirSync(bin);
  writeFileSync(join(bin,'codex'),f.recorder,{mode:0o755});
  writeFileSync(f.binary,'#!/bin/bash\nexit 99\n',{mode:0o755});
  const result=f.install(bin+':/usr/bin:/bin');assert.equal(result.status,0,result.stderr);
  assert.match(readFileSync(f.log,'utf8'),/clonie@clonie/);
});

test('Codex: CLI와 데스크톱 앱이 모두 없으면 설치 완료로 보고하지 않는다',t=>{
  const f=desktopInstaller(t),result=f.install();
  assert.equal(result.status,1);
  assert.match(result.stderr,/CLI or its desktop app was not found/);
  assert.doesNotMatch(result.stdout,/installation finished/);
});
