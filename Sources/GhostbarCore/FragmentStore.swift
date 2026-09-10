import Foundation

/// 저장소가 낼 수 있는 실패. **「깨진 파일」은 여기 없다** — 그건 실패가 아니라
/// 치우고 빈 문서로 여는 정상 경로다(`LoadResult.quarantined`).
public enum FragmentStoreError: Error, Equatable {
    /// 우리가 모르는 (더 큰) 스키마 판. 미래 판 파일을 옛 코드가 덮어쓰지 않게 막는다.
    case unknownSchemaVersion(found: Int, supported: Int)
    /// 읽기 자체가 안 된다 (권한 등). 깨진 JSON 과 다르다 — 내용을 못 봤으니 치우지도 않는다.
    case unreadable(underlying: String)
}

/// 불러온 결과. 무엇이 치워졌는지까지 부르는 쪽에 알린다 — 조용히 삼키면
/// 사용자는 자기 파일이 옆으로 밀린 걸 영영 모른다.
public struct LoadResult: Equatable {
    public var document: CueDocument
    /// 깨진 원본을 옮겨둔 자리. 정상이면 `nil`.
    public var quarantined: URL?
    /// 조각 id → **볼트 상대경로** (`삼성 면접/프로젝트 X/X 개요.md`). #74 A.
    ///
    /// ⚠ **`Fragment` 안이 아니라 여기 사는 이유**: 경로는 파일이 놓인 자리에서 나오는
    /// **파생값**이라 md frontmatter 에 안 쓴다. 조각에 칸을 만들면 그 값이 저장 왕복을
    /// 타고 디스크로 내려가고, 사람이 옵시디언에서 파일을 옮기는 순간 둘이 갈린다.
    ///
    /// ⚠ **볼트가 아닌 저장소(`FragmentStore`)는 이걸 못 채운다** — 파일 하나에 문서가
    /// 통째로 들어서 조각마다의 자리가 없다. 그때는 빈 표이고, 화면은 **전부 미분류 항성**
    /// 으로 그린다 (#74 B 의 규칙 하나: 경로를 못 정하면 `__root`).
    public var paths: [String: String]

    public init(document: CueDocument, quarantined: URL? = nil,
                paths: [String: String] = [:]) {
        self.document = document
        self.quarantined = quarantined
        self.paths = paths
    }
}

/// 조각 저장소 — **디스크의 JSON 문서 하나**가 전부다.
///
/// 파일 하나로 충분한 근거 = 조각 5,000장 순회 2.58ms (`실측`, #4). DB·인덱스가 필요 없는 규모다.
///
/// ## 이 타입이 지키는 것
///
/// - **원자적 쓰기.** 옆에 임시 파일로 다 쓴 뒤 갈아끼운다. 쓰다 죽으면 **원본이 그대로 산다.**
/// - **덮어쓰지 않는다.** 못 읽는 파일을 만나면 타임스탬프 이름으로 옆에 치우고 빈 문서로 연다.
///   사용자 파일을 지우거나 그 위에 쓰는 코드 경로는 여기 없다.
/// - **사람이 읽는다.** `prettyPrinted` + `sortedKeys` + ISO8601 날짜라 눈으로 보고 git diff 가 된다.
public final class FragmentStore {
    public let url: URL
    private let fm: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fm = fileManager
    }

    /// `~/Library/Application Support/Ghostbar/cue.json`.
    ///
    /// ⚠ 폴더 이름이 아직 `Ghostbar` 다 — 가제(Cue)가 굳으면 레포명·번들 ID 와 **한 번에** 옮긴다.
    /// 여기서 혼자 바꾸면 사용자 파일이 뒤에 남는다.
    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Ghostbar", isDirectory: true)
                   .appendingPathComponent("cue.json", isDirectory: false)
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        // ⚠ `.iso8601` 은 **소수점 초를 안 받는다.** 그런데 JS 의 `toISOString()` 은 항상
        //   `.000Z` 를 붙인다 — 화면이 보낸 문서를 우리가 못 읽는 자리가 여기다.
        //   화면 쪽에서도 떼지만, 받는 쪽이 둘 다 받는 것이 맞다 (읽기는 너그럽게).
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: text) ?? fractional.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "ISO8601 날짜가 아니다: \(text)"))
        }
        return d
    }

    // MARK: - 읽기

    public func load() throws -> LoadResult {
        guard fm.fileExists(atPath: url.path) else {
            return LoadResult(document: .empty)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // 내용을 못 봤다. 깨진 것인지 아닌지 **모르므로** 치우지 않는다.
            throw FragmentStoreError.unreadable(underlying: String(describing: error))
        }
        // 판 번호부터 본다. 모르는 미래 판이면 치우지도 열지도 않고 멈춘다 —
        // 그 파일은 새 판 코드가 읽을 수 있는 멀쩡한 파일이다.
        if let head = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let v = head["schemaVersion"] as? Int,
           v > CueDocument.currentSchemaVersion {
            throw FragmentStoreError.unknownSchemaVersion(found: v,
                                                          supported: CueDocument.currentSchemaVersion)
        }
        do {
            return LoadResult(document: try Self.makeDecoder().decode(CueDocument.self, from: data))
        } catch {
            return LoadResult(document: .empty, quarantined: try quarantine())
        }
    }

    /// 깨진 원본을 **옮긴다**(복사 후 삭제가 아니라 rename). 옮기기 전엔 아무것도 안 지운다.
    private func quarantine() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "json" : url.pathExtension
        var dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).\(ext)")
        // ⚠ 같은 초에 두 번 치우면 이름이 겹친다. 겹치면 **덮어쓰지 않고** 번호를 붙인다.
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = url.deletingLastPathComponent()
                .appendingPathComponent("\(base).corrupt-\(stamp)-\(n).\(ext)")
            n += 1
        }
        do {
            try fm.moveItem(at: url, to: dest)
        } catch {
            throw FragmentStoreError.unreadable(underlying: String(describing: error))
        }
        return dest
    }

    // MARK: - 쓰기

    public func save(_ document: CueDocument) throws {
        // 원자적 쓰기는 `AtomicFile` 하나가 든다 — 같은 열 줄이 이 레포에 네 벌이 되려던 자리다.
        try AtomicFile.write(try Self.makeEncoder().encode(document), to: url, fileManager: fm)
    }
}
