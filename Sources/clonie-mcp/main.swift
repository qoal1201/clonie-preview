import Foundation
import MCP
import ClonieMCP

// ★ 둘째 문의 실행파일 (ADR 0007). 실행 모드·볼트·부모 프로세스와의 입출력/수명을 연결한다.
// 논리는 전부 `ClonieMCP` 라이브러리에 있다(`swift test` 가 거기를 잰다).
//
// ⚠ 기본 stdio 모드의 stdout은 MCP 전용이다. 진단은 값을 출력하고 끝내며,
//   명시적인 relay-worker 모드는 부모에게 연결 식별자 JSON만 출력한다.
//   사람에게 하는 말은 전부 stderr 로 — stdout 에 한 글자라도 새면 Claude 쪽 파서가 죽는다.

let usage = """
clonie-mcp — Clonie 저장소를 외부 AI에 연결하는 로컬 MCP 서버 (stdio)
  --vault <경로>   볼트 폴더. 없으면 CLONIE_VAULT → 앱이 고른 자리 → ~/Documents/Clonie
  --version        판을 찍고 끝
  --write-contract 문서 변경 방식만 출력하고 종료 (저장소 접근 없음)
  --tool-catalog   같은 MCP 도구 정의를 JSON으로 출력 (저장소 접근 없음)
  --relay-worker   앱 내부 연결 구성 요소. 명시한 --vault와 stdin의 승인된 설정 필요
  --help           이 글
등록: claude mcp add --scope user clonie -- <이 파일 경로>
"""

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

var vaultArgument: String? = nil
var relayWorker = false
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--vault":
        vaultArgument = it.next()
    case "--relay-worker":
        relayWorker = true
    case "--version":
        print(ClonieMCPVersion.string)
        exit(0)
    case "--write-contract":
        print(ClonieMCPVersion.writeContract)
        exit(0)
    case "--tool-catalog":
        print(try ToolServer.encode(ToolServer.definitions))
        exit(0)
    case "-h", "--help":
        stderr(usage)
        exit(0)
    default:
        stderr("모르는 인자: \(a)\n" + usage)
        exit(2)
    }
}

// Credentials arrive through the parent-owned pipe, never command arguments or disk.
// The parent closes stdin on sign-out/folder change; the worker stops and revokes its grant.
if relayWorker {
    struct Bootstrap: Decodable {
        let endpoint: URL
        let deviceID: UUID
        let vaultID: UUID
        let clientID: String
        let allowProposals: Bool
        let accessToken: String
        let allowLoopback: Bool?
    }
    do {
        guard let vaultArgument, !vaultArgument.isEmpty else { throw RelayFailure.invalidConfiguration }
        var bytes = Data()
        while true {
            guard let byte = try FileHandle.standardInput.read(upToCount: 1), !byte.isEmpty,
                  bytes.count < 32_768 else { throw RelayFailure.invalidConfiguration }
            if byte.first == 10 { break }
            bytes.append(byte)
        }
        let setup = try JSONDecoder().decode(Bootstrap.self, from: bytes)
        let config = try RelayConfiguration(endpoint: setup.endpoint, deviceID: setup.deviceID,
                                            vaultID: setup.vaultID, clientID: setup.clientID,
                                            allowProposals: setup.allowProposals,
                                            allowLoopback: setup.allowLoopback ?? false)
        let vault = try VaultLocator.resolve(argument: vaultArgument)
        let connection = RelayConnection(configuration: config, tools: VaultTools(vaultURL: vault))
        let run = Task {
            try await connection.run(accessToken: { setup.accessToken }, didConnect: { id in
                let message = "{\"grantID\":\"\(id.uuidString.lowercased())\"}\n"
                FileHandle.standardOutput.write(Data(message.utf8))
            })
        }
        let lifetime = Task.detached {
            _ = try? FileHandle.standardInput.read(upToCount: 1)
            run.cancel()
        }
        defer { lifetime.cancel() }
        try await run.value
    } catch is CancellationError {
        exit(0)
    } catch {
        stderr("[clonie-mcp] \((error as? RelayFailure)?.description ?? "relay_disconnected")")
        exit(1)
    }
    exit(0)
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
    try await server.start(transport: CompatibleStdioTransport())
    await server.waitUntilCompleted()
} catch {
    stderr("[clonie-mcp] 서버가 죽었다: \(error)")
    exit(1)
}
