import Foundation
import GhostbarCloud

/// 원문 한 덩이 → **이야기 0~3장, 이 맥에 이미 깔린 공식 CLI 로** (#54 → #55 사다리 2층).
///
/// ★ **CLI 가 둘이다** (#61 B, 그릴 Q4): `claude` · `codex`. 벤더마다 다른 것은 argv 와
/// 로그인 묻는 법뿐이라 `Vendor` 한 구조체로 묶었고, 찾기·스폰·타임아웃·SIGKILL 승격은 한 벌이다.
///
/// ★ **키를 만들지도 만지지도 않는다.** 이 층이 하는 일은 사용자가 **자기 계정으로 로그인해 둔
/// 공식 바이너리를 그대로 스폰해 물어보는 것**뿐이다. 로그인·토큰·설정은 전부 그 CLI 의 것이고
/// 우리는 그 근처에 안 간다 — `block/buzz` 가 같은 자리에서 택한 모양이다
/// (`agent_auth.rs`: *"Buzz never guesses vendor login commands"*, #54).
/// ⚠ **환경변수를 안 세운다 — `PATH` 한 칸만 빼고.** `Process` 는 이 앱의 환경을 그대로
/// 물려준다 — 거기 `ANTHROPIC_API_KEY` 가 있으면 CLI 는 그것을 쓴다. 그건 **사용자의 환경**이고
/// 우리가 지우거나 채우면 그때부터 우리가 인증을 중개하는 것이 된다. **키·토큰 류 주입은 0건**이고
/// 그게 이 단락의 본체다.
/// ★ **그 예외가 `PATH` 다** (`실측 2026-09-02`): Finder 로 띄운 `.app` 의 `$PATH` 는
/// `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이라(`findBin` 머리글의 같은 경고), 그것을 그대로 물려주면
/// **바이너리가 자기 인터프리터를 못 찾는다** — `codex` 는 `#!/usr/bin/env node` 스크립트여서
/// `env: node: No such file or directory` **종료코드 127** 로 죽었다(상태 조회·초안 뽑기 둘 다).
/// 그래서 `run` 이 자식의 `PATH` 를 **찾을 때 쓴 것과 같은 자**(`searchDirs()`)로 넓힌다.
/// 넓히는 것은 **어디를 뒤지나**뿐이고, 인증에 관한 값은 여전히 하나도 더하거나 지우지 않는다.
///
/// ⚠ **정책은 안 닫혔다.** Anthropic 원문은 *"unmodified … with their own Claude
/// subscription"* 을 허용 신호로 두지만, 「제3자 앱이 스폰해 조종하는 것」이 어느 쪽인지는
/// 원문 낱말로 확정되지 않았다 (#54 코멘트, `정관 5조`: 재량을 넓히는 결론엔 낱말이 필요하다).
/// 배선은 그 리스크를 **인지한 채로** 박선호가 지시한 것이다. 다시 열 조건 = Anthropic 회신.
///
/// ⚠ **지시문은 여기서 안 짓는다** — `OutsideDraft.plan` 이 키 클라우드와 **같은 글자**를
/// 준다(`CloudDrafter` 머리글). 이 파일에만 있는 것은 **어떤 argv 로 부르나**뿐이다.
///
/// ⚠ **면접 모드와 무관하다.** 이 길을 여는 화면은 받기(`ingestRender`) 하나이고
/// 그것은 통째로 판정선 경계(`stackRender`) 밖이다 — `CloudDrafter` 와 **같은 자리**다.
/// 그래도 `tests/check_interview_offline.py` 의 낱말표에 이 타입 이름을 세워 뒀다:
/// 여기엔 `URLSession` 이 안 보이는데 **CLI 는 바깥으로 나간다** — 낱말표가 그걸 모르면
/// 이 층이 언젠가 면접 모드에서 닿아도 검사가 조용히 초록이다.
enum CliDrafter {

    // MARK: - 공식 CLI 한 벌 (#61 B — 이 라운드가 codex 를 더했다)

    /// 이 맥에 깔려 있을 수 있는 **공식 CLI 한 벌**. 이름·바이너리·로그인 묻는 법·argv.
    ///
    /// ★ **왜 구조체 하나로 묶었나** (`정관 1조`): 층을 하나 더하는 일이 「같은 코드를 한 벌 더」가
    /// 되면 다음 층에서 또 한 벌이 된다. 벤더마다 다른 것은 **글자 몇 개**뿐이고,
    /// 찾기·스폰·타임아웃·SIGKILL 승격은 전부 같다.
    struct Vendor {
        /// 화면·기록이 쓰는 열쇠. **사람에게 보이는 이름이 아니다.**
        let id: String
        /// 사람이 읽을 이름. 화면 문구가 이 글자를 그대로 쓴다.
        let name: String
        /// 바이너리 이름. **경로가 아니라 이름이다** — `$PATH` 훑기와 고정 목록이 같이 쓴다.
        let binary: String
        /// 홈 밑 고정 후보 (앞의 `~/` 없이). `$PATH` 밖에 깔리는 자리들.
        let homeDirs: [String]
        /// 로그인 상태를 묻는 argv. **싸야 한다** — 창이 뜰 때마다 돈다.
        let statusArgs: [String]
        /// 그 답을 「로그인됨」으로 읽는 법. 종료코드 0 **그리고** 이 판정이어야 참이다.
        /// ⚠ **이 클로저가 보는 글자를 화면으로 보내지 않는다** — `claude auth status` 의 답에는
        ///   이메일·조직 이름이 들어 있다(`실측 2026-08-31`). 나가는 것은 참/거짓뿐이다.
        let loggedIn: (String) -> Bool
        /// 안 깔려 있을 때 사람이 터미널에 칠 한 줄. **화면 문구의 정본이 여기다** (#61 리뷰 발견 ④) —
        /// 전엔 화면(`ChatHTML` 의 `CLI_CMD`)이 같은 표를 한 벌 더 들어서, 벤더가 늘면 두 곳이
        /// 갈릴 자리였다. 나가는 길은 `statuses()` → `onCliStatus` 하나뿐이다.
        /// ⚠ **비밀값이 아니다.** 키·토큰이 붙는 명령을 여기 세우지 않는다 — 이 글자는 화면(WebView)
        ///   으로 그대로 나간다.
        let installCmd: String
        /// 깔려 있는데 로그인이 안 됐을 때의 한 줄. 위와 같은 규율.
        let loginCmd: String
        /// 마지막 답을 **파일로** 낼 수 있나. 그러면 stdout 대신 그 파일을 읽는다.
        let outFile: Bool
        /// 고를 수 있는 모델. ★ **첫 칸이 기본값이다** — 고른 적이 없거나 고른 것이 목록에서
        /// 사라졌으면 여기로 물러선다(`tuning`).
        let models: [Choice]
        /// 고를 수 있는 추론 세기. ★ **빈 배열 = 이 벤더엔 그 칸이 없다** — 화면도 안 그리고
        /// 저장도 안 받는다(`saveTuning`). 「없음」을 화면이 알아서 판정하지 않게 하는 자리다.
        let reasonings: [Choice]
        /// 뽑기 argv. `out` 은 `outFile` 일 때만 뜻이 있다.
        /// ⚠ **조절값이 인자로 들어온다** — 여기서 `UserDefaults` 를 읽지 않는다. 그러면
        ///   이 표가 저장소를 알게 되고, 시험이 argv 를 재려면 저장소를 흔들어야 한다.
        let draftArgs: (_ instructions: String, _ prompt: String, _ out: String,
                        _ tuning: Tuning) -> [String]
    }

    /// 사람이 고를 수 있는 값 하나. `value` 는 **CLI 에 그대로 실리는 글자**이고
    /// `label` 은 화면에 뜨는 글자다.
    ///
    /// ⚠ **빈 `value` = 「CLI 기본」** — 그때는 깃발 자체를 안 넣는다. 이 칸이 있어야
    /// 우리가 모델 이름을 하나도 못 맞히는 판(상류가 이름을 갈아치운 날)에도 이 층이 산다.
    struct Choice {
        let value: String
        let label: String
    }

    /// 한 번 부를 때 실리는 조절값 둘. **빈 글자면 그 깃발을 안 넣는다** — CLI 의 기본을 그대로 둔다.
    struct Tuning {
        let model: String
        let reasoning: String
    }

    /// ★ **claude 층** — argv 의 근거는 아래 벤더 표 주석에 모아 뒀다.
    ///
    /// ★ **기본이 `haiku` 인 근거**: `실측 2026-08-31`(#54 스파이크) — `--model haiku` 로
    ///   **#52 A/B 의 키 클라우드와 동급 품질**이었다(숫자가 전부 살아남고 제목이 결과를 든다).
    ///   그래서 목록의 **첫 칸**이고, 고른 적이 없으면 여기로 떨어진다.
    /// ⚠ **별칭을 쓴다** (`claude --help` 원문: *"Provide an alias for the latest model
    ///   (e.g. 'fable', 'opus', or 'sonnet')"*). 정식 이름(`claude-fable-5`)을 박으면
    ///   그 판이 물러나는 날 이 층이 조용히 죽는다 — 별칭은 상류가 따라 옮겨 준다.
    static let claude = Vendor(
        id: "claude", name: "Claude Code", binary: "claude",
        homeDirs: [".claude/local", ".local/bin", ".bun/bin", ".volta/bin"],
        statusArgs: ["auth", "status"],
        // `실측 2026-08-31`: `claude auth status` 가 **JSON** 을 낸다(0.3초). `loggedIn` 한 칸만 본다.
        loggedIn: { $0.replacingOccurrences(of: " ", with: "").contains("\"loggedIn\":true") },
        installCmd: "npm install -g @anthropic-ai/claude-code", loginCmd: "claude",
        outFile: false,
        models: [Choice(value: "haiku", label: "haiku (기본)"),
                 Choice(value: "sonnet", label: "sonnet"),
                 Choice(value: "opus", label: "opus")],
        // 추론 세기를 고르는 깃발이 `claude --help` 에 없다 (`실측 2026-09-01`). 빈 칸 = 그 줄을 안 그린다.
        reasonings: [],
        draftArgs: { instructions, prompt, _, t in
            var args = ["-p", instructions + "\n\n" + prompt]
            if !t.model.isEmpty { args += ["--model", t.model] }
            args += ["--safe-mode",
                     "--no-session-persistence",
                     "--output-format", "text"]
            return args
        })

    /// ★ **codex 층** (#61 B, 그릴 Q4 — 박선호: *"일단 2개 구독 연결하자"*).
    ///
    /// 왜 이 깃발들인가 (`codex exec --help` 원문 · `실측 2026-08-31`):
    /// - `exec` — 대화창 없이 한 번 답하고 끝낸다. claude 의 `-p` 자리다
    /// - `--skip-git-repo-check` — 작업 폴더가 임시 폴더(=git 레포가 아니다)라 없으면 거절한다
    /// - `--ephemeral` — 세션 파일을 디스크에 안 남긴다. claude 의 `--no-session-persistence` 짝
    /// - `--ignore-user-config` — `$CODEX_HOME/config.toml` 을 안 읽는다. claude 의 `--safe-mode`
    ///   자리이고, 원문이 *"auth still uses CODEX_HOME"* 이라 **구독 로그인은 산다**
    /// - `--color never` — ANSI 부호가 답에 섞이지 않게
    /// - `-s read-only` — 모델이 낸 명령을 실행할 수 있는 상자를 읽기 전용으로 좁힌다
    /// - `-o <파일>` — ★ **출력 정리 플래그.** 원문: *"Specifies file where the last message
    ///   from the agent should be written"*. 이게 그릴이 말한 「노이즈 섞임」의 답이다
    ///
    /// `실측 2026-08-31`(소형 프롬프트 1건, codex-cli 0.146.0): **7.8초** · `-o` 파일과 stdout 이
    /// 둘 다 답 하나뿐이었다. 그릴 실증(37초 · stdout 에 `hook: Stop`·`tokens used` 섞임)은
    /// 깃발이 없던 판이다 — **노이즈의 출처가 사용자 훅이었고 `--ignore-user-config` 가 그것을 끈다.**
    /// ⚠ 그래도 **`-o` 를 정본으로 읽는다.** stdout 이 깨끗한 것은 이 판·이 설정의 실측이고,
    ///   `-o` 는 원문이 약속한 자리다. 파일이 비면 stdout 으로 물러선다(`draftViaCLI`).
    /// ⚠ **기본이 「CLI 기본」이다** — 목록의 첫 칸이 **빈 글자**이고, 그때 `-m` 을 아예 안 넣는다.
    ///   claude 층은 스파이크가 잰 `haiku` 가 있지만 여기는 품질을 잰 것이 없고, 이름을 기본으로
    ///   박으면 그 이름이 사라지는 날 이 층이 조용히 죽는다.
    ///
    /// ★ **모델·추론을 고르는 깃발** (박선호 2026-09-01: *"모델 선택이나 추론 설정도 가능한가?"*).
    ///   `codex exec --help` 원문 · `실측 2026-09-01` (codex-cli 0.146.0):
    /// - `-m, --model <MODEL>` — *"Model the agent should use"*. ⚠ **`-o` 가 아니다** —
    ///   `-o` 는 `--output-last-message <FILE>` 이라, `-o model=…` 은 「model=… 이라는 이름의
    ///   파일에 답을 써라」로 읽혀 **모델은 안 바뀌고 답이 사라진다.**
    /// - `-c, --config <key=value>` — *"Override a configuration value…"*. 추론 세기는
    ///   설정 칸이라 깃발이 따로 없고 이 길로 간다: `-c model_reasoning_effort=<low|medium|high>`.
    ///   `실측 2026-09-01` 양성/음성 대조 — `--strict-config` 를 걸고
    ///   `-c model_reasoning_effort_BOGUS=high` 는 *"unknown configuration field"* 로 **거절**,
    ///   `-c model_reasoning_effort=…` 는 **통과**했다. 즉 이 낱말은 이 판이 아는 칸이다.
    ///   ⚠ **값은 CLI 가 안 가린다** — 없는 세기(`bogus`)를 줘도 그대로 돈다. 목록 밖 글자를
    ///   막는 것은 우리 쪽(`saveTuning`)뿐이다.
    /// ⚠ **모델 이름은 이 맥에서 잰 것이다** (`~/.codex/models_cache.json`, `실측 2026-09-01`:
    ///   기본이 `gpt-5.6-terra`). 그래서 **첫 칸이 「CLI 기본」**이다 — 이름이 통째로 갈려도
    ///   기본 칸은 살아 있고, 죽은 이름이 저장돼 있으면 `tuning` 이 그 칸으로 물러선다.
    static let codex = Vendor(
        id: "codex", name: "Codex CLI", binary: "codex",
        homeDirs: [".local/bin", ".bun/bin", ".volta/bin", ".cargo/bin"],
        statusArgs: ["login", "status"],
        // `실측 2026-08-31`: 로그인돼 있으면 `Logged in using ChatGPT` 한 줄(종료코드 0).
        // ⚠ 「안 됨」 쪽 글자를 못 봐서 **긍정 낱말 + 부정 낱말 배제**로 좁힌다.
        // ⚠ **그 한 줄은 표준출력이 아니라 표준오류로 나온다** (`실측 2026-09-02`:
        //   `codex login status 2>/dev/null` = 빈 글자 · `2>&1 1>/dev/null` = 그 한 줄).
        //   그래서 `statuses()` 가 두 줄기를 같이 먹인다 — 거기 주석이 정본이다.
        loggedIn: { let t = $0.lowercased()
                    return t.contains("logged in") && !t.contains("not logged in") },
        installCmd: "npm install -g @openai/codex", loginCmd: "codex login",
        outFile: true,
        models: [Choice(value: "", label: "CLI 기본"),
                 Choice(value: "gpt-5.6-terra", label: "gpt-5.6-terra"),
                 Choice(value: "gpt-5.6-luna", label: "gpt-5.6-luna"),
                 Choice(value: "gpt-5.5", label: "gpt-5.5"),
                 Choice(value: "gpt-5.4-mini", label: "gpt-5.4-mini")],
        reasonings: [Choice(value: "", label: "CLI 기본"),
                     Choice(value: "low", label: "low"),
                     Choice(value: "medium", label: "medium"),
                     Choice(value: "high", label: "high")],
        draftArgs: { instructions, prompt, out, t in
            var args = ["exec",
                        "--skip-git-repo-check",
                        "--ephemeral",
                        "--ignore-user-config",
                        "--color", "never",
                        "-s", "read-only"]
            if !t.model.isEmpty { args += ["-m", t.model] }
            if !t.reasoning.isEmpty { args += ["-c", "model_reasoning_effort=" + t.reasoning] }
            // ⚠ **프롬프트가 마지막이다** — `codex exec [OPTIONS] [PROMPT]` 라 위치 인자 뒤에
            //   깃발을 붙이면 그 깃발이 프롬프트의 일부로 읽힌다. 새 깃발은 언제나 이 위에.
            args += ["-o", out, instructions + "\n\n" + prompt]
            return args
        })

    /// ★ **사다리 2층 안의 순서** — `claude` 가 먼저다.
    ///
    /// 근거는 취향이 아니라 **실증의 양**이다: claude 층은 #52 A/B · #54 스파이크 · #55 배선까지
    /// 네 번 재서 품질과 지연을 알고 있고(`claude` 벤더의 「기본이 `haiku` 인 근거」),
    /// codex 층은 그 라운드의 **1건**이다.
    /// ⚠ **다시 열 조건**: codex 층 실측이 쌓여 품질·지연에서 앞서면 그때 순서를 바꾼다.
    ///   그 전에 바꾸면 「덜 아는 쪽을 기본으로」가 된다.
    static let vendors: [Vendor] = [claude, codex]

    /// 화면에 「켤 수 있나」를 알려 주는 짐. **경로는 나가지만 홈 디렉터리 이름이 들어간다** —
    /// 그래서 화면으로는 `name`(사람이 읽을 이름)만 보내고 `path` 는 Swift 안에 둔다.
    struct Readiness {
        let ready: Bool
        let id:    String     // 어느 벤더인가 (없으면 빈 글자)
        let name:  String     // 사람에게 보일 이름
        let path:  String     // 찾은 바이너리. 못 찾았으면 빈 글자
    }

    /// 화면이 그리는 **연결 카드 한 줄** (#61 B·C). 키·경로·계정은 안 들어간다.
    struct Status {
        let id: String
        let name: String
        let installed: Bool
        let loggedIn: Bool
        /// 화면이 그대로 세우는 터미널 한 줄 둘. **벤더 표에서 그대로 실린다** (#61 리뷰 발견 ④) —
        /// 화면이 자기 표를 들지 않게 하려고 답에 얹는 것이고, **새 통로가 아니다.**
        let installCmd: String
        let loginCmd: String
        /// 지금 고른 값 둘. **정본은 여기(Swift)다** — 화면이 저장소를 못 읽는다.
        let model: String
        let reasoning: String
        /// 고를 수 있는 것들. ★ **목록도 여기서 실려 나간다** — 화면이 같은 표를 한 벌 더 들면
        /// 벤더·모델 이름이 바뀌는 날 두 곳이 조용히 갈린다(#61 리뷰 발견 ④ 가 `install`·`login`
        /// 두 줄에서 이미 걷어낸 자리다). `reasonings` 가 비면 화면은 그 줄을 안 그린다.
        let models: [Choice]
        let reasonings: [Choice]
    }

    /// CLI 한 번의 결과. **`CloudDrafter.Outcome` 과 같은 모양이다** — 사다리 두 층을
    /// 부르는 쪽(`WKWebViewWrapper.draftFragment`)이 같은 갈림으로 읽게.
    enum Outcome {
        case ok([FragmentDrafter.Draft])
        case fallback(String)
    }

    /// 한 덩이에 주는 시간.
    ///
    /// `실측 2026-08-31`, 같은 611자 문항 답 한 덩이로 두 방식을 겨뤘다(claude 층):
    /// - `--system-prompt` 로 기본 프롬프트를 **갈아 끼운** 판: **90.0초 · 71.3초**
    /// - 지시문을 물음 앞에 **이어 붙인** 판(`--safe-mode` 포함): **21.3초(셸 직접) ·
    ///   38.7초(이 배선 그대로)** — 품질 동일
    /// `추론`: 기본 프롬프트를 갈면 상류 프롬프트 캐시가 통째로 안 맞는다. 그래서 이
    /// 배선은 이어 붙이기다(`claude` 벤더 주석) — 두 벌 우려보다 2~4배 지연이 비쌌다.
    /// 120 = 잰 최댓값(38.7초)의 3배 여유. codex 층은 7.8초라 이 상한에 한참 못 미친다.
    /// ⚠ **여기가 짧으면 모델이 몰린 날 전량이 조용히 온디바이스로 내려간다** — 그게 이
    /// 층이 있으나 마나 해지는 모양이라, 넉넉한 쪽이 싸다. 어차피 못 끝내면 사다리가 받는다.
    /// ⚠ **이 수를 「던져넣기 한 판이 얼마나 걸리나」로 읽지 마라.** 큐가 직렬이라
    /// 20덩이 자소서면 덩이당 25초로도 **한 판이 8분대**다. 상한이 아니라 이 층의 성질이고,
    /// 고칠 자리도 여기가 아니다(#55 후속에서 잴 것).
    static let timeout: TimeInterval = 120

    /// 로그인 상태를 묻는 데 주는 시간. **창이 뜰 때마다 도는 검사**라 짧다 —
    /// `실측 2026-08-31`: `claude auth status` 0.3초 · `codex login status` 0.16초.
    /// ⚠ 넘기면 「모른다」가 아니라 **「로그인 아님」**으로 떨어진다. 화면이 「연결하기」를
    ///   띄우고, 눌러 보면 이미 돼 있는 것이 안 돼 있다고 말하는 것보다 덜 나쁘다.
    static let statusTimeout: TimeInterval = 6

    // MARK: - 찾기

    /// ★ **이 파일 안에서 자가 하나다** — 바이너리를 **찾는 자리**(`findBin`)와 자식에게
    /// **물려주는 자리**(`run`)가 같은 디렉터리 목록을 쓴다. 둘이 갈리면 「우리는 찾았는데 그
    /// 바이너리는 자기 도구를 못 찾는」 모양이 난다 — `실측 2026-09-02` 에 실제로 그랬다
    /// (`run` 머리글).
    /// ⚠ **레포 전체의 규칙이 아니다** (2026-09-02, 리뷰 발견 ⑤ 정정). 다른 스폰 자리 둘은
    /// 여전히 각자의 자를 쓴다 — `Transcriber.findWhisperBin`(고정 후보 셋)과
    /// `DocumentExtractor`(`/usr/bin/unzip` 절대 경로)이고, **둘 다 환경을 안 넓힌다.**
    /// 오늘 문제가 없는 이유는 그 둘이 **네이티브 실행 파일이라 인터프리터를 안 찾기** 때문이지
    /// 이 규칙을 따라서가 아니다. 여기 적힌 「하나」는 이 파일의 두 자리를 가리킨다.
    ///
    /// 순서 = ① 지금 `$PATH` ② `/opt/homebrew/bin` · `/usr/local/bin` ③ **모든 벤더의
    /// `homeDirs` 합집합**(홈 경로로 풀어서). 앞에 온 것이 이긴다(순서 보존 dedup).
    ///
    /// ⚠ **③ 이 벤더별이 아니라 합집합이다.** 그래서 `claude` 를 찾을 때 `.cargo/bin`(codex 쪽
    /// 자리)까지 훑는다. 대신 자가 하나가 유지되고, 벤더가 늘면 그 벤더의 자리가 모두에게 열린다.
    /// ★ **왜 무해한가 — 면이 둘이다** (2026-09-02, 리뷰 발견 ③ 정정. 전 판은 앞의 면만 적었다):
    /// - **찾을 때**(`findBin`): 남의 폴더엔 그 이름의 실행 파일이 없어 그냥 안 걸린다
    /// - **물려줄 때**(`run`): 이 목록이 그대로 자식의 `$PATH` 가 된다 — 그러니 「못 찾을 뿐」이
    ///   아니라 **자식이 거기서 아무 이름이나 집을 수 있다.** 수용하는 근거는 둘이다:
    ///   ① 합집합은 **`$PATH` 뒤**에 붙어 `/usr/bin` 같은 앞자리를 못 가린다(순서 보존 dedup) ·
    ///   ② `homeDirs` 는 전부 `$HOME` 밑이라 **그 사용자가 이미 쓰는 자리**다(우리가 만든 자리도,
    ///   남이 쓰는 자리도 아니다). 이 둘 중 하나라도 깨지는 `homeDirs` 를 더하면 근거가 죽는다.
    static func searchDirs() -> [String] {
        var seen = Set<String>()
        var dirs: [String] = []
        func add(_ d: String) { if !d.isEmpty, seen.insert(d).inserted { dirs.append(d) } }

        for d in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            add(String(d))
        }
        add("/opt/homebrew/bin")
        add("/usr/local/bin")
        let home = NSHomeDirectory()
        for v in vendors { for d in v.homeDirs { add(home + "/" + d) } }
        return dirs
    }

    /// 그 벤더의 바이너리를 **찾아서** 쓴다 — whisper 와 **같은 모양**이다
    /// (`Transcriber.swift` 의 `findWhisperBin`: 후보 경로 목록에서 처음 있는 것).
    ///
    /// ⚠ **`$PATH` 만 믿으면 안 된다.** Finder 로 띄운 `.app` 은 로그인 셸을 안 거쳐
    /// `$PATH` 가 `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이다 — 개발 중 터미널에서 띄우면 되고
    /// 배포판에서만 안 되는, 제일 늦게 발견되는 모양이 된다. 그래서 **훑고 나서 고정 목록**이다
    /// (그 목록이 `searchDirs()`).
    /// ⚠ `fileExists` 가 아니라 `isExecutableFile` 이다 — 있는데 못 돌리는 파일을
    /// 「준비됨」으로 화면에 알리면 토글이 켜진 채로 매번 폴백만 한다.
    static func findBin(_ v: Vendor) -> String? {
        searchDirs()
            .map { $0 + "/" + v.binary }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 이 길을 켤 수 있나. **CLI 를 부르지 않는다** — 파일이 있나만 본다.
    ///
    /// ⚠ **로그인했는지는 여기서 안 본다.** 그걸 알려면 남의 프로세스를 띄워야 하고, 이 함수는
    /// 저장 때마다·창이 뜰 때마다 돈다. 안 돼 있으면 첫 덩이에서 실패하고 사다리가 그 자리에서
    /// 다음 벤더 → 온디바이스로 내려간다 — **조용히 내려가는 것이 이 층의 계약**이다.
    /// 로그인을 실제로 묻는 자리는 `statuses()` 하나이고, 그건 **설정 화면이 열릴 때만** 돈다.
    /// - Returns: `vendors` 순서로 **처음 깔려 있는** 벤더. 하나도 없으면 `ready == false`.
    static func cliReadiness() -> Readiness {
        for v in vendors {
            if let bin = findBin(v) {
                return Readiness(ready: true, id: v.id, name: v.name, path: bin)
            }
        }
        return Readiness(ready: false, id: "", name: vendors[0].name, path: "")
    }

    /// 화면 문구가 쓰는 **바이너리 이름 목록** — 「공식 CLI(claude·codex)가 깔려 있어도 켜져요」.
    static var binaryNames: String { vendors.map(\.binary).joined(separator: "·") }

    // MARK: - 모델·추론 (박선호 2026-09-01: *"모델 선택이나 추론 설정도 가능한가?"*)

    /// 고른 값이 사는 자리. **벤더 id 로 갈린다** — 한 칸에 몰면 벤더가 늘 때 남의 값을 쓴다
    /// (백엔드 키 슬롯이 하나뿐이라 제공자가 갈리면 주인이 없어지던 자리와 같은 모양, #65 ③).
    static func modelKey(_ v: Vendor) -> String { "cliModel." + v.id }
    static func reasoningKey(_ v: Vendor) -> String { "cliReasoning." + v.id }

    /// 이 벤더로 물어볼 때 실릴 값 한 벌.
    ///
    /// ⚠ **목록에 없는 글자는 안 쓴다.** 저장한 뒤에 목록이 바뀔 수 있고(모델 이름은 사라진다),
    /// 그때 죽은 이름을 그대로 실으면 CLI 가 **매번 거절**해 이 층이 통째로 폴백만 한다.
    /// 그런 값은 목록의 **첫 칸**(= 기본)으로 물러선다.
    static func tuning(_ v: Vendor) -> Tuning {
        let d = UserDefaults.standard
        return Tuning(model: pick(d.string(forKey: modelKey(v)), v.models),
                      reasoning: pick(d.string(forKey: reasoningKey(v)), v.reasonings))
    }

    private static func pick(_ saved: String?, _ list: [Choice]) -> String {
        guard let s = saved, list.contains(where: { $0.value == s }) else {
            return list.first?.value ?? ""
        }
        return s
    }

    /// 화면이 고른 값을 저장한다. **목록에 있는 글자만 받는다.**
    ///
    /// ⚠ 화면으로 나갔던 목록이 그대로 돌아오는 길이지만, **통로가 그것을 보증하지 않는다**
    /// (WebView 다). 그래서 받는 쪽에서 다시 목록으로 거른다.
    /// ⚠ **모르는 글자는 그냥 안 저장한다** — 사고를 내지도, 기본값으로 덮지도 않는다.
    /// 덮으면 「고른 적 없는 값이 저장되는」 자리가 되고, 그건 화면이 보여 준 것과 갈린다.
    /// ⚠ 추론 칸이 없는 벤더(`reasonings` 가 빈 배열)는 그 값을 **통째로 안 받는다** —
    /// 빈 목록에는 어떤 글자도 안 들어 있으므로 아래 조건이 그대로 막는다.
    static func saveTuning(vendorId: String, model: String?, reasoning: String?) {
        guard let v = vendors.first(where: { $0.id == vendorId }) else { return }
        if let m = model, v.models.contains(where: { $0.value == m }) {
            UserDefaults.standard.set(m, forKey: modelKey(v))
        }
        if let r = reasoning, v.reasonings.contains(where: { $0.value == r }) {
            UserDefaults.standard.set(r, forKey: reasoningKey(v))
        }
    }

    // MARK: - 로그인 상태 (#61 B — 프론트 설정의 연결 카드)

    /// `statuses()` 가 **마지막에 잰** 로그인. ★ **캐시지 판정이 아니다** — 아직 안 잰 벤더는
    /// 여기 없고, 그건 「로그아웃」이 아니라 **「모른다」**다.
    ///
    /// ⚠ **왜 있나**: 로그인을 아는 자리(`statuses`)와 화면에 「누가 만들어요」를 말하는 자리
    /// (`sendCloudReady`)가 갈려 있었다. 뒤엣것은 창이 뜰 때마다·저장할 때마다 도는 동기 함수라
    /// 남의 프로세스를 못 띄운다 — 그래서 **잰 쪽이 자국을 남기고 말하는 쪽이 그것을 읽는다.**
    /// ⚠ **뽑기 경로는 이걸 안 읽는다**(`draftFragment` 는 `lane` 그대로다). 두드릴 때는 진짜로
    /// 두드려 보는 것이 답이다 — 낡은 자국으로 층을 미리 지우면 **터미널에서 방금 로그인하고
    /// 돌아온 사람**이 그 층을 못 쓴다.
    /// ⚠ **자물쇠가 붙은 상자다. `static var` 딕셔너리로 두면 안 된다** (`실측 2026-09-02`:
    /// 그렇게 뒀더니 첫 저장에서 **`EXC_BAD_ACCESS`로 앱이 죽었다** — 크래시 스택
    /// `Dictionary._Variant.setValue` ← `CliDrafter.statuses()`). **쓰는 쪽은 백그라운드
    /// 태스크**(`statuses` 는 `async`, 협업 스레드에서 돈다)이고 **읽는 쪽은 메인**
    /// (`sendCloudReady`)이라, 전역 가변 저장소를 맨손으로 만지면 안 되는 자리다.
    private final class LoginMemo {
        private let lock = NSLock()
        private var seen: [String: Bool] = [:]
        func get(_ id: String) -> Bool? { lock.lock(); defer { lock.unlock() }; return seen[id] }
        func put(_ pairs: [(String, Bool)]) {
            lock.lock(); defer { lock.unlock() }
            for (id, on) in pairs { seen[id] = on }
        }
    }
    private static let loggedInSeen = LoginMemo()

    /// 그 벤더의 마지막 로그인 자국. **안 재 봤으면 `nil`**(= 모른다).
    static func lastLoggedIn(_ id: String) -> Bool? { loggedInSeen.get(id) }

    /// 벤더마다 「깔렸나 · 로그인됐나」. **설정 화면이 열릴 때만 부른다.**
    ///
    /// ⚠ **나가는 것은 참/거짓과 이름, 그리고 터미널 한 줄 둘뿐이다.** `claude auth status` 는
    /// 이메일·조직 이름·구독 종류까지 내고(`실측 2026-08-31`), 그것을 화면(WebView)에 앉히면
    /// 우리 손을 떠난다. 명령 두 줄은 **벤더 표의 고정 글자**라 그 위험이 없다.
    /// ⚠ **안 깔린 벤더는 CLI 를 안 부른다** — 없는 파일을 스폰하면 사고 하나가 공짜로 는다.
    static func statuses() async -> [Status] {
        // 한 벌 짓는 자리를 하나로 — 명령 두 줄이 세 갈래에 흩어지면 그것부터 갈린다.
        func st(_ v: Vendor, installed: Bool, loggedIn: Bool) -> Status {
            let t = tuning(v)
            return Status(id: v.id, name: v.name, installed: installed, loggedIn: loggedIn,
                          installCmd: v.installCmd, loginCmd: v.loginCmd,
                          model: t.model, reasoning: t.reasoning,
                          models: v.models, reasonings: v.reasonings)
        }
        var out: [Status] = []
        for v in vendors {
            guard let bin = findBin(v), !v.statusArgs.isEmpty else {
                out.append(st(v, installed: false, loggedIn: false))
                continue
            }
            switch await run(bin: bin, args: v.statusArgs, name: v.name, limit: statusTimeout) {
            // ★ **표준출력과 표준오류를 같이 본다** (`실측 2026-09-02`). `codex login status` 는
            //   `Logged in using ChatGPT` 를 **표준오류로** 낸다 — 종료코드는 0이라, 출력만 보면
            //   빈 글자를 판정해 **로그인해 둔 사람에게 「로그인이 필요해요」**라고 말한다.
            //   ⚠ 전 판이 이걸 못 본 이유: 터미널에서 재면 두 줄기가 같은 화면으로 나온다.
            //   ⚠ **뽑기는 이렇게 안 한다**(`draft` 는 표준출력만) — 거긴 섞이면 답이 더러워진다.
            //   ⚠ 나가는 것은 여전히 **참/거짓뿐**이다(이 함수 머리글).
            case .out(let text, let err):
                out.append(st(v, installed: true, loggedIn: v.loggedIn(text + "\n" + err)))
            case .why:
                out.append(st(v, installed: true, loggedIn: false))
            }
        }
        // ★ **잰 것을 자국으로 남긴다** — 동기 자리(`sendCloudReady`)가 이걸 읽어 화면 둘이
        //   같은 값을 말한다. 여기 말고는 이 표를 쓰는 자리가 없다(`lastLoggedIn` 머리글).
        loggedInSeen.put(out.map { ($0.id, $0.loggedIn) })
        return out
    }

    // MARK: - 부르기

    /// 덩이 하나 → 이야기 0~3장. **던지지 않는다.**
    ///
    /// ★ **벤더를 순서대로 탄다** (#61 B). 하나가 어떤 이유로든 안 되면 **그 자리에서 다음 벤더**로
    /// 내려가고, 전부 안 되면 사유를 모아 `.fallback` 을 낸다 — 그러면 부르는 쪽이 온디바이스로
    /// 내려간다. ⚠ 전 판은 「처음 깔린 하나」만 불렀다: claude 가 깔렸는데 로그아웃이면
    /// codex 가 멀쩡해도 **건너뛰어졌다.**
    ///
    /// - Parameter only: **이 벤더 하나만** 탄다 (박선호 2026-09-01, `DrafterChoice`). 사람이
    ///   두뇌를 골랐으면 순서를 타는 것 자체가 그 결정을 뒤집는 것이다 — 그래서 목록을 좁힌다.
    ///   ⚠ **여기서 「안 되면 다음」을 안 끈다**: 목록이 하나면 순회가 한 바퀴로 끝나고,
    ///   그 하나의 사유가 그대로 `.fallback` 으로 나간다. 갈림을 두 벌 두지 않는 자리다.
    static func draftViaCLI(text: String, parts: Int = 1, ask: Bool = false,
                            only: Vendor? = nil) async -> Outcome {
        let instructions: String, prompt: String
        switch OutsideDraft.plan(text: text, parts: parts, ask: ask) {
        case .stop(let why):     return .fallback(why)
        case .none:              return .ok([])
        case .go(let i, let p):  instructions = i; prompt = p
        }

        var whys: [String] = []
        for v in (only.map { [$0] } ?? vendors) {
            guard let bin = findBin(v) else { continue }
            switch await draft(v, bin: bin, instructions: instructions, prompt: prompt) {
            case .ok(let drafts): return .ok(drafts)
            case .fallback(let why): whys.append(why)
            }
        }
        if whys.isEmpty { return .fallback("이 맥에 쓸 수 있는 공식 CLI 가 없어요") }
        return .fallback(whys.joined(separator: " · "))
    }

    /// 벤더 하나에게 한 번 물어본다.
    ///
    /// ⚠ **펜스를 여기서 안 벗긴다.** `실측 2026-08-31`(#54 스파이크): 모델이 지시를 어기고
    ///   ```json 을 두른다 — 그런데 그건 **키 클라우드도 하던 것**이라
    ///   `CloudDraftWire.cloudDrafts` 가 이미 너그럽게 뜯는다(첫 번째로 파싱되는 JSON 덩이).
    ///   여기서 다시 짜면 뜯는 자가 두 벌이 되고, 그 다음부터 두 층이 서로 다른 답을 살린다.
    ///   `정관 1조`.
    private static func draft(_ v: Vendor, bin: String,
                              instructions: String, prompt: String) async -> Outcome {
        let outPath = v.outFile ? tempOutPath(v) : ""
        defer { if !outPath.isEmpty { try? FileManager.default.removeItem(atPath: outPath) } }

        switch await run(bin: bin,
                         args: v.draftArgs(instructions, prompt, outPath, tuning(v)),
                         name: v.name, limit: timeout) {
        case .why(let why):
            return .fallback(why)
        case .out(let stdoutText, _):
            // ★ **마지막 답만 쓴 파일이 정본이다** (`-o`). 비었으면 stdout 으로 물러선다 —
            //   깃발이 그 CLI 판에 없거나 이름이 바뀌었을 때 이 층이 통째로 죽지 않게.
            let fromFile = outPath.isEmpty ? "" : ((try? String(contentsOfFile: outPath,
                                                                encoding: .utf8)) ?? "")
            let text = fromFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? stdoutText : fromFile
            guard let drafts = CloudDraftWire.cloudDrafts(fromText: text,
                                                          limit: FragmentDrafter.maxDrafts) else {
                return .fallback("\(v.name) 가 JSON 이 아닌 답을 냈어요")
            }
            return .ok(drafts.map { FragmentDrafter.Draft(title: $0.title, body: $0.body) })
        }
    }

    /// 마지막 답이 앉을 임시 파일. **볼트가 아니라 임시 폴더다** — 사용자 글이 남을 자리가 아니다.
    private static func tempOutPath(_ v: Vendor) -> String {
        NSTemporaryDirectory() + "clonie-\(v.id)-\(UUID().uuidString).txt"
    }

    /// 스폰 한 번의 결과 둘. ⚠ `Result` 를 안 쓴다 — 그쪽은 실패 자리에 `Error` 를
    /// 요구하는데 여기 실패는 **사용자에게 보일 한국어 한 줄**이지 던질 것이 아니다.
    ///
    /// ★ **성공 자리가 두 짝이다 — 표준출력과 표준오류** (`실측 2026-09-02`). 합쳐서 주지 않는
    /// 이유: **뽑기는 표준출력만 읽어야 한다**(사고 문구가 답에 섞이면 파서가 그걸 먹는다).
    /// 대신 **로그인 판정은 둘 다 봐야 한다** — 아래 `statuses()` 의 근거.
    private enum Run {
        case out(String, err: String)
        case why(String)
    }

    /// 한 번 스폰해 표준출력을 가져온다. **던지지 않는다** — 실패도 값이다.
    ///
    /// ⚠ **작업 폴더를 임시 폴더로 세운다.** 안 세우면 앱이 띄워진 자리(개발 중엔 이 레포)를
    /// 물려받아 CLI 가 그 폴더를 자기 작업 공간으로 읽는다. 깃발이 사용자 설정을 이미 끄지만,
    /// 두 자리 다 막는 쪽이 싸다.
    /// ⚠ **표준입력을 막는다.** `실측 2026-08-31`: 파이프로 물린 stdin 을 codex 가
    /// *"Reading additional input from stdin…"* 로 **영원히 기다린다** — 2분 타임아웃까지 갔다.
    /// ⚠ **표준오류를 다른 스레드가 같이 비운다.** 파이프가 차면 쓰는 쪽(CLI)이 멈춰 서고
    /// 그러면 `readDataToEndOfFile` 과 서로 기다린다 — 교착이다.
    /// ★ **`$PATH` 만 넓혀서 물려준다** (`실측 2026-09-02`, 아래). 나머지 환경은 **그대로**다 —
    /// 이 파일 머리글의 「환경변수를 안 세운다」가 그 뜻이고, 그 예외가 여기 하나뿐이다.
    private static func run(bin: String, args: [String],
                            name: String, limit: TimeInterval) async -> Run {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: bin)
                task.arguments = args
                task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                // ★ **찾은 자와 같은 자로 자식의 `$PATH` 를 넓힌다** (`searchDirs()`).
                //   `실측 2026-09-02`: Finder 로 띄운 `.app` 의 최소 `$PATH` 를 그대로 물려주면
                //   `codex`(= `#!/usr/bin/env node` 스크립트)가 `env: node: No such file or
                //   directory` **종료코드 127** 로 죽는다 — 우리는 바이너리를 찾았는데 그 바이너리가
                //   자기 인터프리터를 못 찾는 자리다. **`PATH` 한 칸만 바꾼다.**
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = searchDirs().joined(separator: ":")
                task.environment = env
                task.standardInput = FileHandle.nullDevice
                let out = Pipe(), err = Pipe()
                task.standardOutput = out
                task.standardError  = err

                let errBox = ByteBox()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    errBox.data = err.fileHandleForReading.readDataToEndOfFile()
                    errDone.signal()
                }
                do {
                    try task.run()
                } catch {
                    errDone.signal()
                    cont.resume(returning: .why(
                        "\(name) 를 못 띄웠어요 — \((error as NSError).localizedDescription)"))
                    return
                }
                let killed = FlagBox()
                let killer = DispatchWorkItem {
                    guard task.isRunning else { return }
                    killed.set()
                    task.terminate()
                    // ⚠ SIGTERM 을 무시하는 프로세스면 `waitUntilExit()` 가 영원히 안 풀린다 —
                    //   5초 유예 뒤 SIGKILL 로 승격한다 (matt 리뷰 발견, 2026-08-31).
                    DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                        if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: killer)

                let outData = out.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                killer.cancel()
                errDone.wait()

                if killed.value {
                    cont.resume(returning: .why("\(name) 가 \(Int(limit))초 안에 답을 못 냈어요"))
                    return
                }
                let text = String(data: outData, encoding: .utf8) ?? ""
                guard task.terminationStatus == 0 else {
                    // ⚠ 사용자에게 그대로 보이는 글자다 — **길이를 자르고 줄을 편다.**
                    //   CLI 의 사고 문구엔 경로가 들어올 수 있고, 그건 화면에 앉을 것이 아니다.
                    let raw = String(data: errBox.data, encoding: .utf8) ?? ""
                    let one = raw.split(whereSeparator: \.isNewline)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .first { !$0.isEmpty } ?? ""
                    let detail = one.isEmpty ? "" : " — \(one.prefix(140))"
                    cont.resume(returning: .why(
                        "\(name) 가 거절했어요 (코드 \(task.terminationStatus))\(detail)"))
                    return
                }
                cont.resume(returning: .out(text,
                                            err: String(data: errBox.data, encoding: .utf8) ?? ""))
            }
        }
    }
}

/// 스레드 둘이 같이 보는 칸. **자물쇠 없이 쓰면 경쟁이다.**
/// ⚠ 이 상자들이 파일 안에 사는 이유: 밖에서 쓸 일이 없고, 밖으로 내면 「범용 상자」가 되어
/// 다음 사람이 여기 기능을 더한다. `정관 1조` — 걷으면 다시 일어나는 것을 못 쓰면 안 짓는다.
/// ★ **이 파일의 자물쇠 상자는 셋이다** (2026-09-02, 리뷰 발견 ② 정정 — 전 판은 *「이 둘」* 이라
/// 적어 셋 중 둘만 덮었다): 여기 `ByteBox`·`FlagBox` 와, `CliDrafter` 안의 `LoginMemo`.
/// ⚠ **합치지 않는다.** 사는 자리가 다르고(그쪽은 `static let` 하나를 끼고 산다) 담는 것도
/// 다르다 — 합치면 「범용 상자」가 되고, 그게 이 단락이 막으려는 바로 그것이다.
private final class ByteBox: @unchecked Sendable {
    private let lock = NSLock()
    private var v = Data()
    var data: Data {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
    func set() { lock.lock(); v = true; lock.unlock() }
}
