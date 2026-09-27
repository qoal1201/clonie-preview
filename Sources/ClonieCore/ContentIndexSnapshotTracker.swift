/// 내용 색인의 실제 입력만 담는다. `asked` 같은 별도 기록과 파일 목록 메타데이터가 바뀌어도
/// 조각·질문이 같으면 이미 준비된 벡터를 그대로 쓸 수 있다.
public struct ContentIndexSnapshot: Equatable, Sendable {
    public let fragments: [Fragment]
    public let questions: [Question]

    public init(document: CueDocument) {
        fragments = document.fragments
        questions = document.questions
    }
}

/// 같은 색인 입력의 중복 요청을 막고, 실패한 입력은 다음 전달에서 다시 시도하게 한다.
///
/// `ready` 와 `pending` 을 따로 두는 이유는 새 입력을 색인하는 동안 이전 입력이 다시
/// 전달될 수 있기 때문이다. 현재 pending 과 다른 입력은 이전 ready 와 같더라도 새 요청으로
/// 시작해, 화면에 전달된 문서와 마지막으로 도착할 벡터가 어긋나지 않게 한다.
public struct ContentIndexSnapshotTracker: Sendable {
    private var ready: ContentIndexSnapshot?
    private var pending: ContentIndexSnapshot?

    public init() {}

    /// 새 색인을 시작해야 하면 `true`를 돌려주고 그 입력을 pending 으로 잡는다.
    public mutating func begin(_ snapshot: ContentIndexSnapshot) -> Bool {
        if pending == snapshot { return false }
        if pending == nil, ready == snapshot { return false }
        // 다른 입력을 시작하면 화면은 기존 벡터를 즉시 버린다. tracker 의 ready 도 같이
        // 무효화해야 새 입력 실패 뒤 옛 입력이 돌아왔을 때 실제 벡터를 다시 만들 수 있다.
        ready = nil
        pending = snapshot
        return true
    }

    /// 현재 pending 과 같은 성공만 ready 로 확정한다. 대체된 옛 콜백은 상태를 못 바꾼다.
    public mutating func markReady(_ snapshot: ContentIndexSnapshot) {
        guard pending == snapshot else { return }
        ready = snapshot
        pending = nil
    }

    /// 현재 pending 과 같은 실패를 걷어 다음 동일 입력 전달이 다시 색인을 시작하게 한다.
    public mutating func markFailed(_ snapshot: ContentIndexSnapshot) {
        guard pending == snapshot else { return }
        pending = nil
    }

    /// 볼트를 바꾸면 이전 볼트의 ready/pending 입력을 모두 버린다.
    public mutating func reset() {
        ready = nil
        pending = nil
    }
}
