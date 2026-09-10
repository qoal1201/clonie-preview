// swift-tools-version:5.9
import PackageDescription

// ⚠ 타깃이 셋이 된 이유 = #8. executable 은 `swift test` 를 못 받는다 —
// 저장 로직을 잠그려면 **라이브러리 타깃**으로 뽑아야 한다. `GhostbarCore` 가 그것이고
// 이 레포 첫 Swift 테스트 타깃이 그 위에 선다.
// 이름은 가제(Cue)가 굳으면 레포명·번들 ID 와 **한 번에** 옮기는 목록에 얹는다.
let package = Package(
    name: "Ghostbar",
    platforms: [.macOS("26.0")],   // ⚠ 문자열 형식 — tools 5.9 엔 `.v26` 심볼이 없다 (#7 실측)
    // ★ 이 레포의 **유일한** 외부 의존 (2026-09-03, #77, ADR 0007). 상류 공식 SDK 그대로 —
    //   정관 1조. ⚠ 앱 타깃 `Ghostbar` 는 이것에 의존하지 않는다: MCP 는 **둘째 문**이고
    //   앱 바이너리에 NIO 가 들어가면 안 된다. `실측 2026-09-03`: tools 5.9 호스트에 SDK(tools 6.1)가
    //   그대로 걸렸다 — 도구체인(6.3.3)이 정한다.
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        .target(
            name: "GhostbarCore",
            path: "Sources/GhostbarCore"
        ),
        // ⚠ 타깃이 넷이 된 이유 = #31. 임베딩을 `Sources/Ghostbar/Services/` 에 두면
        //   **executable 안이라 `swift test` 가 못 부른다** — 위 `GhostbarCore` 를 뽑은 것과
        //   똑같은 이유다. #31 의 인수 조건이 「파이썬과 점수가 일치하나」를 테스트로 잠그는 것이라
        //   테스트가 부를 수 있는 자리, 즉 **라이브러리 타깃**이어야 했다.
        //   `GhostbarCore` 에 얹지 않고 새로 뽑은 이유: #30 이 그 타깃을 병렬로 만지고 있다.
        .target(
            name: "GhostbarEmbedding",
            path: "Sources/GhostbarEmbedding"
        ),
        // ⚠ 타깃이 다섯이 된 이유 = #32. 내용 그래프는 **조각(`GhostbarCore`)과
        //   벡터(`GhostbarEmbedding`)가 만나는 자리**인데, 그 만남을 어느 한쪽에 넣으면
        //   ① `GhostbarCore` 가 CoreML 을 들어 이식 경계(ADR 0003)가 깨지거나
        //   ② `GhostbarEmbedding` 이 문서 타입을 들어 #31 의 점수 자물쇠가 문서 스키마에 묶인다.
        //   의존이 Index → {Core, Embedding} 한 방향뿐이라 둘 다 지금 모양 그대로 남는다.
        //   앱 층(`Sources/Ghostbar/`)에 두지 않은 이유는 위 둘과 똑같다 — executable 은
        //   `swift test` 가 못 부른다.
        .target(
            name: "GhostbarIndex",
            dependencies: ["GhostbarCore", "GhostbarEmbedding"],
            path: "Sources/GhostbarIndex"
        ),
        // ⚠ 타깃이 여섯이 된 이유 = #51. 「더 좋은 정리」(사용자 키로 조각 뽑기)의 **전선** —
        //   요청 짓기와 **답 뜯기**다. 위 셋과 **똑같은 이유**로 뽑았다: executable 은
        //   `swift test` 가 못 부른다. 걷으면 무엇이 다시 일어나나 = **클라우드 답 파싱이
        //   검사 밖으로 나간다** — 제공자가 답 모양을 바꿔도 아무것도 안 빨개진다.
        //   ⚠ 지시문·설정 읽기는 여기 없다(앱 층 `Services/CloudDrafter.swift`). 이 타깃은
        //     `BackendConfig`·`FragmentDrafter` 를 안 든다 — 들면 앱 타깃에 의존하게 된다.
        .target(
            name: "GhostbarCloud",
            path: "Sources/GhostbarCloud"
        ),
        .target(name: "GhostbarDocuments", path: "Sources/GhostbarDocuments"),
        .testTarget(name: "GhostbarDocumentsTests", dependencies: ["GhostbarDocuments"], path: "tests/GhostbarDocumentsTests"),
        .executableTarget(
            name: "Ghostbar",
            dependencies: ["GhostbarCore", "GhostbarEmbedding", "GhostbarIndex", "GhostbarCloud", "GhostbarDocuments"],
            path: "Sources/Ghostbar",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        // ⚠ 경로가 소문자 `tests/` 다. 이 레포엔 이미 `tests/`(파이썬 검사)가 있고
        //   맥 파일시스템은 대소문자를 안 가려 `Tests/` 를 만들면 **같은 폴더에 들어간다** —
        //   그런데 git 은 가린다. 그래서 `Tests/…` 로 두면 파일이 커밋에서 조용히 빠지고
        //   대소문자를 가리는 체크아웃(CI·리눅스)에서 `swift test` 가 대상을 잃는다.
        //   `실측 2026-08-28`: 실제로 한 커밋이 그렇게 나갔다.
        .testTarget(
            name: "GhostbarCoreTests",
            dependencies: ["GhostbarCore"],
            path: "tests/GhostbarCoreTests"
        ),
        // ★ 점수 일치 자물쇠(#31). `tests/fixtures/embedding_reference.json` 이 기준면이고
        //   이 타깃이 그걸 먹는다. ⚠ 모델이 없는 환경에서 **조용히 skip 하지 않는다** —
        //   왜 그런지는 `tests/GhostbarEmbeddingTests/ScoreParityTests.swift` 머리글에 있다.
        .testTarget(
            name: "GhostbarEmbeddingTests",
            dependencies: ["GhostbarEmbedding"],
            path: "tests/GhostbarEmbeddingTests"
        ),
        // ★ 내용 그래프 자물쇠(#32). 증분이 실제로 안 돌리나 · 모델 없을 때 안 죽나 ·
        //   이웃 문턱이 두 무리를 실제로 가르나. 문턱의 근거 분포를 **여기가 다시 잰다** —
        //   모델이 바뀌면 상수와 분포가 갈리고 빨개진다.
        .testTarget(
            name: "GhostbarIndexTests",
            dependencies: ["GhostbarIndex"],
            path: "tests/GhostbarIndexTests"
        ),
        // ★ 클라우드 전선 자물쇠(#51). 캔드 픽스처로 **답 뜯기**를, `URLProtocol` 목으로
        //   **다녀오는 길**을 잰다. ⚠ 진짜 키로는 안 잰다 — 그건 사람만 할 수 있다.
        .testTarget(
            name: "GhostbarCloudTests",
            dependencies: ["GhostbarCloud"],
            path: "tests/GhostbarCloudTests"
        ),
        // ★ 둘째 문 타깃 셋(라이브러리·실행·시험)이 생긴 이유 = #77 (brain#56 ⓐ, ADR 0007). Claude 가
        //   stdio MCP 로 같은 볼트를 읽고 쓴다. 도구 논리는 **라이브러리**로 뽑았다: 위 넷과 똑같은 이유
        //   (executable 은 `swift test` 를 못 받는다). 실행 타깃은 main.swift 한 장이다.
        //   ⚠ 이 둘만 `MCP` 를 든다. `Ghostbar`(앱)가 여기 의존하기 시작하면 NIO 가 앱에 링크된다.
        .target(
            name: "ClonieMCP",
            dependencies: ["GhostbarCore", "GhostbarEmbedding", "GhostbarIndex", "GhostbarDocuments",
                           .product(name: "MCP", package: "swift-sdk")],
            path: "Sources/ClonieMCP"
        ),
        .executableTarget(
            name: "clonie-mcp",
            dependencies: ["ClonieMCP", .product(name: "MCP", package: "swift-sdk")],
            path: "Sources/clonie-mcp"
        ),
        // ★ 둘째 문 자물쇠. `TwoProcessTests` 가 **빌드된 `clonie-mcp` 를 실제로 띄운다** —
        //   그래서 이 타깃은 실행 타깃과 같은 `swift test` 에서 돈다(SwiftPM 이 제품을 먼저 만든다).
        .testTarget(
            name: "ClonieMCPTests",
            dependencies: ["ClonieMCP", .product(name: "MCP", package: "swift-sdk")],
            path: "tests/ClonieMCPTests"
        )
    ]
)
