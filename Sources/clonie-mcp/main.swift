import Foundation
import MCP
import ClonieMCP

// ★ 둘째 문의 실행파일 (ADR 0007). 하는 일은 셋뿐이다 — 인자 읽기 · 볼트 정하기 · stdio 로 서기.
// 논리는 전부 `ClonieMCP` 라이브러리에 있다(`swift test` 가 거기를 잰다).
//
// ⚠ **stdout 은 MCP 전용이다.** 여기서 `print` 는 `--version` 하나뿐이고, 그건 서버가 서기 전이다.
//   사람에게 하는 말은 전부 stderr 로 — stdout 에 한 글자라도 새면 Claude 쪽 파서가 죽는다.

let usage = """
clonie-mcp — Clonie 볼트를 Claude 에 여는 로컬 MCP 서버 (stdio)
  --vault <경로>   볼트 폴더. 없으면 CLONIE_VAULT → 앱이 고른 자리 → ~/Documents/Clonie
  --version        판을 찍고 끝
  --help           이 글
등록: claude mcp add --scope user clonie -- <이 파일 경로>
"""

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

var vaultArgument: String? = nil
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--vault":
        vaultArgument = it.next()
    case "--version":
        print(ClonieMCPVersion.string)
        exit(0)
    case "-h", "--help":
        stderr(usage)
        exit(0)
    default:
        stderr("모르는 인자: \(a)\n" + usage)
        exit(2)
    }
}

let vaultURL: URL
do {
    vaultURL = try VaultLocator.resolve(argument: vaultArgument)
} catch {
    stderr("볼트 자리를 못 정했다: \(error)")
    exit(1)
}

let tools = VaultTools(vaultURL: vaultURL)
let server = await ToolServer.make(tools: tools)
stderr("[clonie-mcp \(ClonieMCPVersion.string)] 볼트: \(vaultURL.path)")

do {
    try await server.start(transport: StdioTransport())
    await server.waitUntilCompleted()
} catch {
    stderr("[clonie-mcp] 서버가 죽었다: \(error)")
    exit(1)
}
