import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(CoreServices)
import CoreServices
#endif

/// 볼트를 **밖에서** 고쳤을 때 알려주는 신호 (ADR 0003 §1 — 옵시디언으로 같은 파일을 고친다).
///
/// ## 신호까지만이다
///
/// 이 타입은 *"볼트가 바뀌었다"* 만 말한다. **다시 읽을지는 부르는 쪽이 정한다** —
/// 사용자가 조각을 쓰는 중에 문서를 갈아끼우면 쓰던 글이 날아간다. 그래서 여기서
/// `load()` 를 부르지 않는다.
///
/// ## 무엇을 안 세나
///
/// - `.clonie/` 안 (우리가 쓰는 자리다 — 우리 저장이 우리를 깨우면 무한이 된다)
/// - 도구 내부/캐시 경로. 일반 파일·폴더 변경도 지도에 반영한다.
///
/// ⚠ **우리가 쓴 것도 신호가 된다.** 저장 직후 한 번 깨어나는 것은 정상이고,
/// 부르는 쪽이 「안 바뀌었으면 아무 일도 안 일어난다」로 흡수한다 (`VaultStore.sameOnDisk`).
///
/// # 한계
///
/// - FSEvents 는 **macOS 것**이다. `#if canImport(CoreServices)` 로 갈라 두었고,
///   그 밖에서는 아무 신호도 안 낸다(조용히 꺼지는 게 아니라 **애초에 안 켜진다** —
///   `isSupported` 가 false 다). Windows 이식은 여기 한 구현을 더 붙이는 자리다.
/// - 폴더가 통째로 옮겨지면 감시가 그 자리를 따라간다(FSEvents 기본). 새 자리를 볼트로
///   삼지는 않는다 — 그건 부르는 쪽의 설정이다.
public final class VaultWatcher {

    /// 이 플랫폼에서 감시가 가능한가. **거짓이면 `start()` 는 아무 일도 안 한다.**
    public static var isSupported: Bool {
        #if canImport(CoreServices)
        return true
        #else
        return false
        #endif
    }

    private let url: URL
    private let latency: TimeInterval
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var started = false

    #if canImport(CoreServices)
    private var stream: FSEventStreamRef?
    #endif

    /// - Parameters:
    ///   - latency: 이만큼 모았다 한 번에 준다. 옵시디언 저장 한 번이 이벤트 여러 개다.
    public init(vaultURL: URL,
                latency: TimeInterval = 0.5,
                queue: DispatchQueue = DispatchQueue(label: "clonie.vault.watch"),
                onChange: @escaping () -> Void) {
        // FSEvents 는 POSIX realpath 로 알려준다 (/var → /private/var).
        // Foundation 의 resolvingSymlinksInPath() 는 이 macOS 루트 별칭을
        // 풀지 않으므로, 새 prefix 경계 비교 전에 실제 경로를 맞춘다.
        let resolved = vaultURL.resolvingSymlinksInPath()
        self.url = URL(fileURLWithPath: Self.realPath(resolved.path), isDirectory: true)
        self.latency = latency
        self.queue = queue
        self.onChange = onChange
    }

    private static func realPath(_ path: String) -> String {
        #if canImport(Darwin)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if path.withCString({ realpath($0, &buffer) != nil }) {
            return String(cString: buffer)
        }
        #endif
        return path
    }

    deinit { stop() }

    public func start() {
        guard !started else { return }
        #if canImport(CoreServices)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let list = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
            if me.interesting(Array(list.prefix(count))) { me.onChange() }
        }

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            // ⚠ `UseCFTypes` 를 빼면 `paths` 가 **C 문자열 배열**로 온다 —
            //   그걸 `NSArray` 로 읽으면 조용히 틀리는 게 아니라 **터진다**(실측: signal 11).
            UInt32(kFSEventStreamCreateFlagUseCFTypes
                   | kFSEventStreamCreateFlagFileEvents
                   | kFSEventStreamCreateFlagNoDefer))
        else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        started = true
        #endif
    }

    public func stop() {
        #if canImport(CoreServices)
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
        started = false
        #endif
    }

    /// 이 경로들 중 **우리가 신경 쓸 것**이 하나라도 있나. (시험이 이걸 직접 잰다)
    func interesting(_ paths: [String]) -> Bool {
        paths.contains { Self.isInteresting($0, vaultPath: url.path) }
    }

    static func isInteresting(_ path: String, vaultPath: String) -> Bool {
        let vaultPath = vaultPath.hasSuffix("/") ? String(vaultPath.dropLast()) : vaultPath
        if path == vaultPath { return true }
        guard path.hasPrefix(vaultPath + "/") else { return false }
        return !VaultEntryCatalog.isExcluded(relativePath: String(path.dropFirst(vaultPath.count + 1)))
    }
}
