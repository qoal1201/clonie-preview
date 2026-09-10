import CryptoKit
import Foundation

/// 한 Markdown 파일을 읽었을 때의 불변 표식. 내용 바이트가 하나라도 달라지면 fingerprint가 달라진다.
public struct VaultFileRevision: Codable, Equatable, Sendable {
    public let relativePath: String
    public let fingerprint: String
    public let byteCount: Int

    fileprivate init(relativePath: String, fingerprint: String, byteCount: Int) {
        self.relativePath = relativePath
        self.fingerprint = fingerprint
        self.byteCount = byteCount
    }
}

/// `loadVersioned()`가 읽은 Markdown 파일별 기준선.
///
/// 값 자체가 불변이라, 같은 `VaultStore`가 나중에 다시 읽어도 편집을 시작할 때 받은 기준선은
/// 바뀌지 않는다. `baseline`은 저장 시 변경 여부와 frontmatter 보존에 쓰는 내부 짐이다.
public struct VaultRevision: Equatable, Sendable {
    public let vaultPath: String
    public let files: [String: VaultFileRevision]
    let baseline: [String: ParsedFile]
    public let entries: [String: VaultEntry]

    init(vaultPath: String, files: [String: VaultFileRevision],
         baseline: [String: ParsedFile], entries: [String: VaultEntry] = [:]) {
        self.vaultPath = vaultPath
        self.files = files
        self.baseline = baseline
        self.entries = entries
    }

    /// 최신 전체 기준선 위에서, 로컬 편집을 시작한 파일만 더 오래된 기준선으로 되돌린다.
    ///
    /// 외부 reload 뒤 최신 리비전 전체를 쓰면 같은 파일의 외부 편집을 덮고, 오래된 리비전 전체를
    /// 쓰면 받아들인 다른 파일까지 거짓 충돌이 된다. 이 합성은 그 둘을 파일 id로 가른다.
    public func preservingFileBaselines(for fragmentIDs: Set<String>,
                                        from editingRevision: VaultRevision) throws -> VaultRevision {
        guard vaultPath == editingRevision.vaultPath else {
            throw VaultRevisionError.differentVault(expected: editingRevision.vaultPath,
                                                     actual: vaultPath)
        }
        var mergedFiles = files
        var mergedBaseline = baseline
        for id in fragmentIDs {
            if let old = editingRevision.files[id], let parsed = editingRevision.baseline[id] {
                mergedFiles[id] = old
                mergedBaseline[id] = parsed
            } else {
                // 편집을 시작할 때 없던 id다. 그 사이 같은 id가 생겼어도 최신 파일을 덮지 않고
                // 새 파일 쓰기 경로로 보내는 쪽이 안전하다.
                mergedFiles.removeValue(forKey: id)
                mergedBaseline.removeValue(forKey: id)
            }
        }
        return VaultRevision(vaultPath: vaultPath, files: mergedFiles, baseline: mergedBaseline, entries: entries)
    }

    /// 오래 살아야 하는 편집 기준선에서 필요한 파일만 남긴다.
    ///
    /// 화면이 외부 reload를 오래 받는 동안 옛 전체 볼트 판을 붙들면 메모리가 `reload × 볼트`로
    /// 자란다. 실제 저장에 필요한 것은 손댄 파일의 기준선뿐이다.
    public func selectingFileBaselines(for fragmentIDs: Set<String>) -> VaultRevision {
        VaultRevision(vaultPath: vaultPath,
                      files: files.filter { fragmentIDs.contains($0.key) },
                      baseline: baseline.filter { fragmentIDs.contains($0.key) })
    }
}

public struct VersionedLoadResult: Equatable {
    public let result: LoadResult
    public let revision: VaultRevision
}

public struct VaultSaveResult: Equatable, Sendable {
    /// 저장한 문서와 함께 다음 조건부 저장에 넘길 기준선.
    public let revision: VaultRevision
    /// 조각 id → 볼트 상대경로. 새 조각의 실제 파일명도 바로 돌려준다.
    public let paths: [String: String]
}

public struct FileConflict: Equatable, Sendable {
    public enum DiskState: String, Codable, Equatable, Sendable {
        case modified
        case deleted
    }

    public let fragmentID: String
    public let relativePath: String
    public let diskState: DiskState
    /// 외부에서 고친 현재 파일을 읽을 수 있었으면 그 모양. 삭제면 `nil`이다.
    public let diskFragment: Fragment?
    /// 앱/MCP가 쓰려던 내용을 별도 파일로 보존한 자리. 삭제 요청에는 쓸 내용이 없어 `nil`이다.
    public let attemptedCopyURL: URL?

    public init(fragmentID: String, relativePath: String, diskState: DiskState,
                diskFragment: Fragment? = nil, attemptedCopyURL: URL? = nil) {
        self.fragmentID = fragmentID
        self.relativePath = relativePath
        self.diskState = diskState
        self.diskFragment = diskFragment
        self.attemptedCopyURL = attemptedCopyURL
    }
}

/// 같은 파일이 읽은 뒤 달라져 저장을 거부한 결과. 현재 디스크와 쓰려던 문서를 둘 다 보존한다.
public struct VaultConflictError: Error, Equatable, Sendable, LocalizedError {
    public let conflicts: [FileConflict]
    public let attemptedDocument: CueDocument

    public var errorDescription: String? {
        let paths = conflicts.map(\.relativePath).joined(separator: ", ")
        return "읽은 뒤 바뀐 파일이 있어 저장하지 않았다: \(paths)"
    }
}

public enum VaultRevisionError: Error, Equatable, Sendable, LocalizedError {
    case differentVault(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .differentVault:
            return "다른 볼트에서 읽은 리비전으로 저장할 수 없다"
        }
    }
}

public enum VaultPathError: Error, Equatable, Sendable, LocalizedError {
    case invalidRelativePath(String)
    case outsideVault(String)
    case occupied(String)
    case pathForExistingFragment(String)
    case unknownFragment(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRelativePath(let path): return "Markdown 상대경로가 올바르지 않다: \(path)"
        case .outsideVault(let path): return "경로가 볼트 밖을 가리킨다: \(path)"
        case .occupied(let path): return "경로에 이미 파일이 있다: \(path)"
        case .pathForExistingFragment(let id): return "기존 조각의 경로는 이 저장에서 바꿀 수 없다: \(id)"
        case .unknownFragment(let id): return "문서에 없는 새 조각의 경로다: \(id)"
        }
    }
}

/// 볼트 — **폴더 하나가 저장소다** (ADR 0003 §1·2).
///
/// ```
/// <볼트>/                         유저 소유. 아무 md 나 있어도 된다
/// ├── 배포 스크립트를 갈아엎었다.md   조각 1장 = md 1장
/// ├── 메모/옛날 회고.md              하위 폴더도 읽는다
/// └── .clonie/                    ★ 사이드카 — 기계의 것
///     ├── document.json           질문 목록 등 **md 로 못 적는 상태**
///     ├── asked.json              입력 기록 — 태양·면접 질문과 그때의 색 (ADR 0006 §③). 박자가 달라 따로 산다
///     ├── migrated-cue.json.bak   옛 JSON 문서 원본 (첫 열기에 옮겨온다)
///     └── trash/                  앱에서 지운 조각. **파일을 지우지 않는다**
/// ```
///
/// ## 이 타입이 지키는 것
///
/// - **사용자 파일을 안 지운다.** 앱에서 조각을 지우면 `.clonie/trash/` 로 **옮긴다.**
/// - **안 바뀐 파일은 안 쓴다.** 화면은 매번 문서 전체를 보내는데, 그걸 그대로 디스크에
///   내리면 남의 옵시디언 볼트가 **한 번 열 때마다 통째로 다시 쓰인다.** 조각의 알맹이가
///   같으면 그 파일은 손대지 않는다 — 남의 서식·`tags`·수정시각이 그대로 산다.
/// - **모르는 frontmatter 를 되돌려 놓는다** (`MarkdownFragment`).
/// - **원자적 쓰기.** 옆에 임시 파일로 다 쓴 뒤 갈아끼운다 (`FragmentStore` 와 같은 방식).
///
/// ## 왜 질문은 md 가 아닌가
///
/// 질문은 **조각이 아니다** — 조각이 `questionIds` 로 가리키는 색인의 축이다(#8).
/// 그걸 md 로 내리면 사용자 볼트에 앱 전용 파일이 늘고, 사람이 고치면 id 가 어긋난다.
/// ADR 0003 §2 의 *"기계의 지능은 사이드카에 산다"* 가 이 자리다.
///
/// ⚠ **AppKit 을 안 든다** — 이식 경계(ADR 0003). 여기 `import AppKit` 이 생기면
/// Windows 이식이 이 파일부터 막힌다.
public final class VaultStore {

    /// 볼트 폴더.
    public let vaultURL: URL
    /// 옛 JSON 문서 자리. 첫 열기에 이걸 md 로 옮긴다. `nil` 이면 마이그레이션을 안 한다.
    public let legacyJSONURL: URL?

    let fm: FileManager
    /// 마지막으로 **디스크에서 읽은 모양.** 저장할 때 「안 바뀐 것」을 가리는 기준이다.
    private var snapshot: [String: ParsedFile] = [:]
    /// `snapshot`을 만들 때 읽은 실제 파일 바이트의 SHA-256. 내용 비교와 별개인 외부 변경 자물쇠다.
    private var snapshotRevisions: [String: VaultFileRevision] = [:]
    private var snapshotEntries: [String: VaultEntry] = [:]
    /// 마지막으로 읽은 질문 목록·판. **안 바뀌었으면 `document.json` 을 안 쓴다** (ADR 0007 —
    /// 둘째 문이 조각만 더할 때 사이드카를 두고 앱과 경주하지 않게). `nil` 이면 읽은 적 없다 → 쓴다.
    private var lastHead: (schemaVersion: Int, questions: [Question])?
    /// 마지막으로 읽거나 쓴 입력 기록. 같으면 안 쓴다(`lastHead` 와 같은 규율).
    private var lastAsked: [AskedEntry]?

    public init(vaultURL: URL, legacyJSONURL: URL? = nil, fileManager: FileManager = .default) {
        self.vaultURL = vaultURL
        self.legacyJSONURL = legacyJSONURL
        self.fm = fileManager
    }

    /// `~/Documents/Clonie` — 아무것도 안 고른 사람의 볼트.
    ///
    /// ⚠ Application Support 가 아니라 **Documents** 다. 볼트는 사용자가 파인더로 열고
    /// 옵시디언으로 붙이는 물건이라, 숨은 자리에 두면 「내 파일」이 아니게 된다.
    public static func defaultVaultURL(fileManager: FileManager = .default) throws -> URL {
        let docs = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        return docs.appendingPathComponent("Clonie", isDirectory: true)
    }

    // MARK: - 자리

    public var sidecarURL: URL { vaultURL.appendingPathComponent(".clonie", isDirectory: true) }
    public var trashURL: URL { sidecarURL.appendingPathComponent("trash", isDirectory: true) }
    /// 질문 목록이 사는 곳. **`FragmentStore` 를 그대로 쓴다** — 원자적 쓰기·격리·미래 판 거부가
    /// 이미 거기 있고, 우리 것을 또 지으면 그 셋을 두 벌 유지하게 된다 (정관 1조).
    public var documentJSONURL: URL { sidecarURL.appendingPathComponent("document.json") }
    /// 입력 기록 (ADR 0006 §③). `document.json` 과 **다른 파일** — 질문 축은 드물게, 기록은 면접마다 바뀐다.
    /// 한 파일에 두면 면접 한 번에 질문 축 파일이 통째로 다시 쓰인다.
    public var askedJSONURL: URL { sidecarURL.appendingPathComponent("asked.json") }
    /// 옛 JSON 원본을 옮겨둘 자리.
    public var migratedBackupURL: URL {
        sidecarURL.appendingPathComponent("migrated-cue.json.bak")
    }

    private var questionStore: FragmentStore { FragmentStore(url: documentJSONURL, fileManager: fm) }

    // MARK: - 읽기

    public func load() throws -> LoadResult {
        try loadVersioned().result
    }

    /// 문서와 그 문서를 편집하기 시작한 파일별 기준선을 한 번에 읽는다.
    public func loadVersioned() throws -> VersionedLoadResult {
        try ensureVaultExists()
        let migrationNotice = try migrateLegacyIfNeeded()

        let head = try questionStore.load()
        let questions = head.document.questions
        // 격리했으면 읽은 것이 없다 — 다음 저장이 다시 만든다. `lastHead` 를 채우면(빈 문서와
        // 「안 바뀌었다」로 겹쳐) 질문이 그대로인 저장이 영영 document.json 을 안 다시 만든다.
        lastHead = head.quarantined != nil ? nil : (head.document.schemaVersion, questions)
        let known = Set(questions.map(\.id))

        let entries = try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entries()
        snapshotEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })

        var parsed: [ParsedFile] = []
        var revisionsByPath: [String: VaultFileRevision] = [:]
        for rel in entries.filter({ $0.kind == "file" && $0.manageable && ["md", "markdown"].contains(($0.path as NSString).pathExtension.lowercased()) }).map(\.path) {
            let url = vaultURL.appendingPathComponent(rel)
            // 못 읽는 파일 하나가 볼트 전체를 막지 않는다. 건너뛰고 나머지를 연다.
            guard let data = try? Data(contentsOf: url), let text = decodeText(data) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let created = (attrs?[.creationDate] as? Date) ?? Date()
            let updated = (attrs?[.modificationDate] as? Date) ?? created
            parsed.append(MarkdownFragment.parse(text: text, relativePath: rel,
                                                 fallbackDates: (created, updated),
                                                 knownQuestionIds: known))
            revisionsByPath[rel] = Self.fileRevision(data: data, relativePath: rel)
        }
        // 같은 id 가 둘이면 **경로 순으로 앞선 것이 이긴다** — 뒤엣것을 지우지 않고 그냥 안 든다.
        var byID: [String: ParsedFile] = [:]
        for p in parsed.sorted(by: { $0.relativePath < $1.relativePath }) where byID[p.fragment.id] == nil {
            byID[p.fragment.id] = p
        }
        snapshot = byID
        snapshotRevisions = byID.reduce(into: [:]) { out, pair in
            out[pair.key] = revisionsByPath[pair.value.relativePath]
        }

        // 순서가 화면의 목록 순서다. 만든 시각 → 경로. **폴더 열거 순서에 안 기댄다.**
        let fragments = byID.values
            .sorted {
                $0.fragment.createdAt == $1.fragment.createdAt
                    ? $0.relativePath < $1.relativePath
                    : $0.fragment.createdAt < $1.fragment.createdAt
            }
            .map(\.fragment)

        // 입력 기록은 **따로 사는 파일**이다. 여기서 읽어 문서에 얹어 화면까지 한 짐으로 보낸다.
        let (asked, askedQuarantined) = loadAskedLog()
        lastAsked = asked

        let doc = CueDocument(schemaVersion: head.document.schemaVersion,
                              questions: questions,
                              fragments: fragments,
                              asked: asked)
        // ★ **자리를 같이 낸다** (#74 A). 여기까지는 `ParsedFile.relativePath` 로 있었고
        //   화면으로 넘기며 버려졌다 — 「우주」의 항성이 볼트 폴더라 그 값이 그림의 축이다.
        //   ⚠ 저장은 **이 표를 안 읽는다.** 되쓸 자리는 `snapshot` 이 든다(아래 `save`) —
        //     화면이 돌려주는 값에 파일 자리를 맡기면 남의 볼트가 화면 버그 하나로 재배치된다.
        let result = LoadResult(document: doc,
                          // ⚠ 기록 격리도 **띠로 올린다** — 면접 한 판의 기록이 말 없이 비면 안 된다(정관 10조).
                          quarantined: head.quarantined ?? migrationNotice ?? askedQuarantined,
                          paths: byID.mapValues(\.relativePath))
        return VersionedLoadResult(result: result, revision: currentRevision())
    }

    /// 없으면 빈 기록. **깨졌으면 옆으로 치우고** 빈 기록 — 못 읽는 사이드카 하나가 볼트를 막지 않는다
    /// (`FragmentStore` 의 격리와 같은 모양, 다만 여기는 판 거부까지 안 간다: 기록은 축이 아니다).
    /// - Returns: 기록과, 치웠으면 **치운 자리**(화면 띠가 그 이름을 말한다 — `sendDocument`). 정상이면 `nil`.
    private func loadAskedLog() -> ([AskedEntry], URL?) {
        guard fm.fileExists(atPath: askedJSONURL.path) else { return ([], nil) }
        do {
            let data = try Data(contentsOf: askedJSONURL)
            return (try FragmentStore.makeDecoder().decode(AskedLog.self, from: data).entries, nil)
        } catch {
            let bad = sidecarURL.appendingPathComponent("asked.json.bad-\(Int(Date().timeIntervalSince1970))")
            try? fm.moveItem(at: askedJSONURL, to: bad)
            return ([], bad)
        }
    }

    private func decodeText(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        // UTF-8 이 아닌 md 도 있다 (옛 편집기). 거절하지 않고 한 번 더 시도한다.
        return String(data: data, encoding: .utf16) ?? String(decoding: data, as: UTF8.self)
    }

    /// 볼트 안의 md 상대경로. 일반 dot 폴더는 포함하고 도구 내부·symlink·패키지는 제외한다.
    public func markdownRelativePaths() throws -> [String] {
        try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entries().filter {
            $0.kind == "file" && $0.manageable && ["md", "markdown"].contains(($0.path as NSString).pathExtension.lowercased())
        }.map(\.path)
    }

    // MARK: - 쓰기

    public func save(_ document: CueDocument) throws {
        _ = try performSave(document, expecting: currentRevision(), newPaths: [:])
    }

    /// `loadVersioned()` 때 읽은 파일만 조건부로 고친다.
    ///
    /// 같은 파일이 외부에서 수정·삭제됐으면 디스크 원본은 그대로 두고, 쓰려던 내용은
    /// `.clonie/conflicts/`에 별도 보존한 뒤 `VaultConflictError`를 던진다. 다른 파일의 외부
    /// 변경은 이 저장을 막지 않는다. 반환 리비전은 호출자가 보낸 문서의 다음 기준선이며,
    /// 외부에서 바뀐 다른 파일까지 합치려면 저장 성공 뒤 `loadVersioned()` 결과를 화면에 반영한다.
    ///
    /// 이는 프로세스 사이의 낙관적 검사다. 임의의 외부 프로그램을 잠그는 OS 잠금은 아니다.
    public func save(_ document: CueDocument, expecting revision: VaultRevision,
                     newPaths: [String: String] = [:]) throws -> VaultSaveResult {
        try performSave(document, expecting: revision, newPaths: newPaths)
    }

    /// MCP는 Markdown만 갱신한다. 오래된 질문·입력 기록을 받아도 사이드카에 쓰지 않는다.
    public func saveFragments(_ document: CueDocument, expecting revision: VaultRevision,
                              newPaths: [String: String] = [:]) throws -> VaultSaveResult {
        try performSave(document, expecting: revision, newPaths: newPaths, writeMetadata: false)
    }

    private func performSave(_ document: CueDocument,
                             expecting revision: VaultRevision,
                             newPaths: [String: String], writeMetadata: Bool = true) throws -> VaultSaveResult {
        try ensureVaultExists()
        let actualVault = vaultURL.standardizedFileURL.path
        guard revision.vaultPath == actualVault else {
            throw VaultRevisionError.differentVault(expected: revision.vaultPath, actual: actualVault)
        }
        let explicitPaths = try validatedNewPaths(newPaths, document: document, revision: revision)

        let conflicts = try findConflicts(document: document, revision: revision)
        if !conflicts.isEmpty {
            throw preservingAttempts(for: conflicts, document: document, revision: revision)
        }

        // 질문·판 번호부터. 조각 파일이 반쯤 쓰이더라도 축은 남는다.
        // ⚠ 단 **읽었을 때와 같으면 안 쓴다** — 「안 바뀐 파일은 안 쓴다」(머리글)가 사이드카에도 걸린다.
        if writeMetadata && (lastHead?.schemaVersion != document.schemaVersion || lastHead?.questions != document.questions) {
            try questionStore.save(CueDocument(schemaVersion: document.schemaVersion,
                                               questions: document.questions,
                                               fragments: []))
            lastHead = (document.schemaVersion, document.questions)
        }

        // ★ 입력 기록은 **따로**, 그리고 **온 것만** 쓴다. `nil` = 이 저장은 기록을 모른다(MCP·옛 화면) —
        //   그때 파일을 지우거나 비우면 면접 한 번의 기록이 남의 저장에 지워진다.
        if writeMetadata, let asked = document.asked, asked != lastAsked {
            let data = try FragmentStore.makeEncoder().encode(AskedLog(entries: asked))
            try AtomicFile.write(data, to: askedJSONURL, fileManager: fm)
            lastAsked = asked
        }

        let baseline = revision.baseline
        // 명시 경로를 먼저 예약한다. 앞의 자동 이름 조각이 그 자리를 차지하면 뒤 조각이 덮어쓴다.
        var used = Set(baseline.values.map(\.relativePath)).union(explicitPaths.values)
        var next: [String: ParsedFile] = [:]
        var nextRevisions: [String: VaultFileRevision] = [:]

        for f in document.fragments {
            if let old = baseline[f.id] {
                if Self.sameOnDisk(old.fragment, f) {
                    next[f.id] = old            // ★ 안 바뀌었다 — 파일을 안 건드린다
                    nextRevisions[f.id] = revision.files[f.id]
                    continue
                }
                if let conflict = try fileConflict(fragmentID: f.id, baseline: old,
                                                   expected: revision.files[f.id],
                                                   knownQuestionIDs: Set(document.questions.map(\.id))) {
                    throw preservingAttempts(for: [conflict], document: document,
                                             revision: revision)
                }
                let text = MarkdownFragment.render(f, preservedFrontmatter: old.preservedFrontmatter)
                try writeAtomically(text, to: vaultURL.appendingPathComponent(old.relativePath))
                next[f.id] = ParsedFile(fragment: f, relativePath: old.relativePath,
                                        preservedFrontmatter: old.preservedFrontmatter,
                                        hadFrontmatterID: true)
                nextRevisions[f.id] = Self.fileRevision(data: Data(text.utf8),
                                                        relativePath: old.relativePath)
            } else {
                let rel = explicitPaths[f.id] ?? uniqueRelativePath(for: f, taken: used)
                used.insert(rel)
                let url = vaultURL.appendingPathComponent(rel)
                try fm.createDirectory(at: url.deletingLastPathComponent(),
                                       withIntermediateDirectories: true)
                let text = MarkdownFragment.render(f)
                try writeNewAtomically(text, to: url, relativePath: rel)
                next[f.id] = ParsedFile(fragment: f, relativePath: rel, hadFrontmatterID: true)
                nextRevisions[f.id] = Self.fileRevision(data: Data(text.utf8), relativePath: rel)
            }
        }

        // 사라진 조각 = 사용자가 앱에서 지운 것. **지우지 않고 옮긴다.**
        //
        // ⚠ **읽은 적 없으면 아무것도 안 옮긴다.** `snapshot` 은 *이 세션이 실제로 읽어낸* 것만
        //   담는다 — 읽기가 실패했을 때(사이드카가 미래 판이라거나) 화면은 **빈 문서**를 받고
        //   씨앗 하나를 저장한다. 그때 디스크를 훑어 맞췄다면 그 한 장 말고 **볼트 전체가
        //   쓰레기통으로 간다.** 못 읽은 것을 지우는 길은 여기 없다 — 대신 조각 하나가
        //   겹치는 이름으로 더 생길 뿐이고(`uniqueRelativePath` 가 덮어쓰지 않는다), 그쪽이 싸다.
        for (id, old) in baseline where next[id] == nil {
            if let conflict = try fileConflict(fragmentID: id, baseline: old,
                                               expected: revision.files[id],
                                               knownQuestionIDs: Set(document.questions.map(\.id))) {
                throw preservingAttempts(for: [conflict], document: document,
                                         revision: revision)
            }
            try moveToTrash(old.relativePath)
        }
        snapshot = next
        snapshotRevisions = nextRevisions
        snapshotEntries = Dictionary(uniqueKeysWithValues: try VaultEntryCatalog(rootURL: vaultURL, fileManager: fm).entries().map { ($0.path, $0) })
        return VaultSaveResult(revision: currentRevision(), paths: next.mapValues(\.relativePath))
    }

    private func currentRevision() -> VaultRevision {
        VaultRevision(vaultPath: vaultURL.standardizedFileURL.path,
                      files: snapshotRevisions, baseline: snapshot, entries: snapshotEntries)
    }

    static func fileRevision(data: Data, relativePath: String) -> VaultFileRevision {
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return VaultFileRevision(relativePath: relativePath,
                                 fingerprint: "sha256:" + fingerprint,
                                 byteCount: data.count)
    }

    private func findConflicts(document: CueDocument,
                               revision: VaultRevision) throws -> [FileConflict] {
        let incoming = document.fragments.reduce(into: [String: Fragment]()) { $0[$1.id] = $1 }
        let known = Set(document.questions.map(\.id))
        var conflicts: [FileConflict] = []

        for (id, old) in revision.baseline.sorted(by: { $0.key < $1.key }) {
            let intended = incoming[id]
            guard intended == nil || !Self.sameOnDisk(old.fragment, intended!) else { continue }
            if let conflict = try fileConflict(fragmentID: id, baseline: old,
                                               expected: revision.files[id],
                                               knownQuestionIDs: known) {
                conflicts.append(conflict)
            }
        }
        return conflicts
    }

    private func fileConflict(fragmentID: String, baseline: ParsedFile,
                              expected: VaultFileRevision?,
                              knownQuestionIDs: Set<String>) throws -> FileConflict? {
        guard let expected else { return nil }
        let url = vaultURL.appendingPathComponent(baseline.relativePath)
        guard fm.fileExists(atPath: url.path) else {
            return FileConflict(fragmentID: fragmentID, relativePath: baseline.relativePath,
                                diskState: .deleted)
        }
        let data = try Data(contentsOf: url)
        let actual = Self.fileRevision(data: data, relativePath: baseline.relativePath)
        guard actual != expected else { return nil }
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        let created = (attrs?[.creationDate] as? Date) ?? Date()
        let updated = (attrs?[.modificationDate] as? Date) ?? created
        let disk = decodeText(data).map {
            MarkdownFragment.parse(text: $0, relativePath: baseline.relativePath,
                                   fallbackDates: (created, updated),
                                   knownQuestionIds: knownQuestionIDs).fragment
        }
        return FileConflict(fragmentID: fragmentID, relativePath: baseline.relativePath,
                            diskState: .modified, diskFragment: disk)
    }

    private func preservingAttempts(for conflicts: [FileConflict], document: CueDocument,
                                    revision: VaultRevision) -> VaultConflictError {
        let preserved = conflicts.map { conflict in
            guard let attempted = document.fragments.first(where: { $0.id == conflict.fragmentID }),
                  let old = revision.baseline[conflict.fragmentID]
            else { return conflict }
            let copy = preserveConflictCopy(attempted, baseline: old)
            return FileConflict(fragmentID: conflict.fragmentID,
                                relativePath: conflict.relativePath,
                                diskState: conflict.diskState,
                                diskFragment: conflict.diskFragment,
                                attemptedCopyURL: copy)
        }
        return VaultConflictError(conflicts: preserved, attemptedDocument: document)
    }

    private func validatedNewPaths(_ requested: [String: String], document: CueDocument,
                                   revision: VaultRevision) throws -> [String: String] {
        guard !requested.isEmpty else { return [:] }
        let incomingIDs = Set(document.fragments.map(\.id))
        var taken = Set(revision.baseline.values.map { Self.pathCollisionKey($0.relativePath) })
        var validated: [String: String] = [:]

        for (id, rel) in requested.sorted(by: { $0.key < $1.key }) {
            guard revision.baseline[id] == nil else {
                throw VaultPathError.pathForExistingFragment(id)
            }
            guard incomingIDs.contains(id) else { throw VaultPathError.unknownFragment(id) }
            try validateRelativeMarkdownPath(rel)
            let key = Self.pathCollisionKey(rel)
            guard !taken.contains(key), !fm.fileExists(atPath: vaultURL.appendingPathComponent(rel).path)
            else { throw VaultPathError.occupied(rel) }
            taken.insert(key)
            validated[id] = rel
        }
        return validated
    }

    private func validateRelativeMarkdownPath(_ rel: String) throws {
        let components = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let ext = (rel as NSString).pathExtension.lowercased()
        guard !rel.isEmpty, !rel.hasPrefix("/"), !rel.contains("\\"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.hasPrefix(".") }),
              ext == "md" || ext == "markdown"
        else { throw VaultPathError.invalidRelativePath(rel) }

        let lexicalBase = vaultURL.standardizedFileURL.path
        let resolvedBase = vaultURL.resolvingSymlinksInPath().standardizedFileURL.path
        let destination = vaultURL.appendingPathComponent(rel).standardizedFileURL
        guard destination.path.hasPrefix(lexicalBase + "/") else {
            throw VaultPathError.outsideVault(rel)
        }

        // 기존 상위 폴더의 symlink를 모두 푼 실제 목적지가 볼트 안인지 확인한다.
        var cursor = vaultURL.resolvingSymlinksInPath().standardizedFileURL
        for component in components.dropLast() {
            cursor.appendPathComponent(component, isDirectory: true)
            if fm.fileExists(atPath: cursor.path) {
                cursor = cursor.resolvingSymlinksInPath().standardizedFileURL
            }
            guard cursor.path == resolvedBase || cursor.path.hasPrefix(resolvedBase + "/") else {
                throw VaultPathError.outsideVault(rel)
            }
        }
    }

    /// 충돌한 편집 내용을 숨은 사이드카에 새 파일로 남긴다. 실패해도 오류의 attemptedDocument는 남는다.
    private func preserveConflictCopy(_ attempted: Fragment, baseline: ParsedFile) -> URL? {
        let folder = sidecarURL.appendingPathComponent("conflicts", isDirectory: true)
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        let stamp = Frontmatter.iso(Date()).replacingOccurrences(of: ":", with: "-")
        let original = (baseline.relativePath as NSString).lastPathComponent
        var destination = folder.appendingPathComponent("\(stamp)-\(original)")
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(stamp)-\(n)-\(original)")
            n += 1
        }
        let text = MarkdownFragment.render(attempted,
                                           preservedFrontmatter: baseline.preservedFrontmatter)
        do {
            try writeAtomically(text, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func pathCollisionKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    /// 디스크에 있는 것과 **같은가**. 날짜는 **초까지만** 본다 —
    /// 파일이 담는 정밀도가 초라, 밀리초까지 재면 열 때마다 「달라졌다」가 되어 볼트가 통째로 다시 쓰인다.
    static func sameOnDisk(_ a: Fragment, _ b: Fragment) -> Bool {
        func sec(_ d: Date) -> Int { Int(d.timeIntervalSince1970.rounded(.down)) }
        // ⚠ 씨앗 표식도 **여기 들어야 한다.** 안 들면 사람이 씨앗을 고쳐 표식을 뗐을 때
        //   「알맹이가 같다」로 읽혀 파일이 안 다시 쓰이고, 재기동하면 표식이 되살아난다.
        return a.id == b.id && a.title == b.title && a.body == b.body
            && a.questionIds == b.questionIds
            && (a.seed ?? false) == (b.seed ?? false)
            && sec(a.createdAt) == sec(b.createdAt) && sec(a.updatedAt) == sec(b.updatedAt)
    }

    /// 제목에서 파일명을 만든다. 겹치면 번호를 붙인다 — **덮어쓰지 않는다.**
    private func uniqueRelativePath(for f: Fragment, taken: Set<String>) -> String {
        var base = Self.slug(f.title)
        if base.isEmpty { base = Self.slug(f.id) }
        if base.isEmpty { base = "조각" }
        var rel = base + ".md"
        var n = 2
        let takenKeys = Set(taken.map(Self.pathCollisionKey))
        while takenKeys.contains(Self.pathCollisionKey(rel))
                || fm.fileExists(atPath: vaultURL.appendingPathComponent(rel).path) {
            rel = "\(base) \(n).md"
            n += 1
        }
        return rel
    }

    /// 파일명으로 못 쓰는 글자만 걷는다. **공백은 남긴다** — 사람이 읽는 이름이 목적이다.
    static func slug(_ title: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var s = title.components(separatedBy: banned).joined(separator: " ")
        s = s.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }   // 숨은 파일이 되면 우리가 다시 못 읽는다
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > 60 { s = String(s.prefix(60)).trimmingCharacters(in: .whitespaces) }
        return s
    }

    private func moveToTrash(_ rel: String) throws {
        let src = vaultURL.appendingPathComponent(rel)
        guard fm.fileExists(atPath: src.path) else { return }
        try fm.createDirectory(at: trashURL, withIntermediateDirectories: true)
        let stamp = Frontmatter.iso(Date()).replacingOccurrences(of: ":", with: "-")
        let name = (rel as NSString).lastPathComponent
        var dest = trashURL.appendingPathComponent("\(stamp)-\(name)")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = trashURL.appendingPathComponent("\(stamp)-\(n)-\(name)")
            n += 1
        }
        try fm.moveItem(at: src, to: dest)
    }

    private func writeAtomically(_ text: String, to url: URL) throws {
        try AtomicFile.write(text, to: url, fileManager: fm)
    }

    /// 새 파일 전용 원자적 쓰기. 목적지가 검증 뒤 생겨도 `moveItem`이 실패하므로 절대 교체하지 않는다.
    /// `internal`인 것은 경주에서 가장 중요한 "create only" 성질을 실제 파일로 직접 시험하기 위해서다.
    func writeNewAtomically(_ text: String, to url: URL, relativePath: String) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try Data(text.utf8).write(to: temporary, options: .atomic)
        do {
            // `AtomicFile`과 달리 존재 여부를 보고 replace하지 않는다. move의 EEXIST가 자물쇠다.
            try fm.moveItem(at: temporary, to: url)
        } catch {
            try? fm.removeItem(at: temporary)
            if fm.fileExists(atPath: url.path)
                || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil {
                throw VaultPathError.occupied(relativePath)
            }
            throw error
        }
    }

    // MARK: - 첫 열기 · 마이그레이션

    private func ensureVaultExists() throws {
        try fm.createDirectory(at: vaultURL, withIntermediateDirectories: true)
    }

    /// 사이드카가 없으면 **첫 열기**다. 그때 한 번만 옛 JSON 을 md 로 옮긴다.
    ///
    /// - Returns: 옛 파일이 깨져 있어 격리된 자리 (있으면).
    @discardableResult
    private func migrateLegacyIfNeeded() throws -> URL? {
        if fm.fileExists(atPath: sidecarURL.path) { return nil }   // 이미 열어본 볼트다
        try fm.createDirectory(at: sidecarURL, withIntermediateDirectories: true)

        guard let legacy = legacyJSONURL, fm.fileExists(atPath: legacy.path) else { return nil }
        let old = FragmentStore(url: legacy, fileManager: fm)
        // ⚠ 미래 판(`unknownSchemaVersion`)은 **던진다.** 못 읽는 문서를 반쯤 옮기면
        //   원본이 옆으로 가고 알맹이는 사라진다.
        let result = try old.load()
        if let q = result.quarantined { return q }   // 깨진 파일 — 옮길 것이 없다

        for f in result.document.fragments {
            let rel = uniqueRelativePath(for: f, taken: [])
            try writeAtomically(MarkdownFragment.render(f),
                                to: vaultURL.appendingPathComponent(rel))
        }
        try questionStore.save(CueDocument(schemaVersion: result.document.schemaVersion,
                                           questions: result.document.questions,
                                           fragments: []))
        // 원본 보존. **옮긴다** — 두 벌이 살아 있으면 어느 것이 정본인지 다음 세션이 모른다.
        if fm.fileExists(atPath: migratedBackupURL.path) {
            try? fm.removeItem(at: migratedBackupURL)   // 우리가 만든 것만 치운다
        }
        do {
            try fm.moveItem(at: legacy, to: migratedBackupURL)
        } catch {
            // 못 옮기면 **복사라도** 남긴다. 원본은 그대로 두고 (지우지 않는다) 넘어간다.
            try? fm.copyItem(at: legacy, to: migratedBackupURL)
        }
        return nil
    }
}
