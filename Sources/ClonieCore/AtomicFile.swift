import Foundation

/// **반쯤 쓰인 파일을 남기지 않는 쓰기.** 이 레포에서 디스크에 앉는 것은 전부 여기를 지난다.
///
/// 같은 폴더에 임시 이름으로 다 쓴 뒤 갈아끼운다. ⚠ **반드시 같은 폴더**여야 한다 —
/// 다른 볼륨에 쓰면 rename 이 복사가 되고, 그 순간 원자성이 사라진다.
///
/// ## 왜 함수 하나로 뽑았나
///
/// `FragmentStore`·`VaultStore` 가 **각자 같은 열 줄을 들고 있었다.** #32 가 사이드카 파일
/// 둘을 더하면서 그게 넷이 될 자리였다 — 넷 중 하나만 고치면 그 파일만 조용히 안 원자적이 된다.
///
/// ⚠ **AppKit·CoreML 을 안 든다** — 이식 경계(ADR 0003). `ClonieCore` 의 다른 파일과 같다.
public enum AtomicFile {

    /// 부모 폴더까지 만들고 원자적으로 쓴다.
    public static func write(_ data: Data, to url: URL,
                             fileManager fm: FileManager = .default) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp, options: .atomic)
        do {
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            // 갈아끼우기가 실패했으면 **임시 파일을 남기지 않는다** — 볼트에 쓰레기가 쌓인다.
            try? fm.removeItem(at: tmp)
            throw error
        }
    }

    public static func write(_ text: String, to url: URL,
                             fileManager fm: FileManager = .default) throws {
        try write(Data(text.utf8), to: url, fileManager: fm)
    }
}
