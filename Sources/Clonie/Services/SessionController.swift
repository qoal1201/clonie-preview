import Foundation
import ClonieCore

/// Main-thread session owner. Rendering and window visibility never start/stop capture.
/// Snapshots are queued in order; only this controller mutates a selected record.
final class SessionController {
    let vaultURL: URL
    let store: SessionStore
    private(set) var record: SessionRecord?
    var onChange: ((SessionRecord?) -> Void)?
    var onError: ((String) -> Void)?
    private var writing: Task<Bool, Never>?
    /// Retained until disk acknowledgement; never render a failed review as completed.
    private var pendingRecordReview: (id: String, status: String)?
    private var busy = false
    private var finishingTask: Task<Bool, Never>?
    private var reviewTask: Task<Void, Never>?
    private var reviewGeneration = 0
    private(set) var currentQuestionID: String?
    private var querySpeaker = "them"
    private var latestIngestEpoch: Int?
    private var resumeEpochFloor: Int?
    private var questionReceiptOrder: [String: Int] = [:]
    private var nextQuestionOrder = 0
    private var currentQuestionOrder = 0
    private(set) var records: [SessionRecord] = []
    var capturing: Bool { record.map { [.preparing, .active, .paused, .finishing].contains($0.state) } ?? false }

    init(vaultURL: URL) {
        self.vaultURL = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        store = SessionStore(vaultURL: self.vaultURL)
    }

    @MainActor func recover() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await store.recoverInterrupted()
            let listed = try await store.listWithIssues()
            records = listed.records
            for index in records.indices where records[index].analysisStatus == "running" {
                records[index].analysisStatus = "interrupted"
                records[index].analysisMessage = "로컬 제안이 중단됐습니다. 다시 제안받거나 직접 기록할 수 있습니다."
                try await store.save(records[index])
            }
            onChange?(record)
            if !listed.issues.isEmpty {
                let names = listed.issues.prefix(3).map { URL(fileURLWithPath: $0.path).lastPathComponent }
                    .joined(separator: ", ")
                let remainder = listed.issues.count > 3 ? " 외 \(listed.issues.count - 3)개" : ""
                onError?("세션 기록 \(listed.issues.count)개를 읽지 못했습니다. 정상 기록은 계속 사용할 수 있습니다: \(names)\(remainder)")
            }
        } catch { onError?("세션 기록을 읽지 못했습니다: \(error.localizedDescription)") }
    }

    @MainActor func start(system: Bool = true) async -> Bool {
        guard !busy, !capturing else { return false }
        busy = true
        defer { busy = false }
        guard await flush() else { return false }
        reviewGeneration += 1
        reviewTask?.cancel(); reviewTask = nil
        currentQuestionID = nil
        latestIngestEpoch = nil
        resumeEpochFloor = nil
        questionReceiptOrder = [:]
        nextQuestionOrder = 0
        currentQuestionOrder = 0
        querySpeaker = system ? "them" : "me"
        record = SessionRecord(vaultPath: vaultURL.path, startedAt: Date().timeIntervalSince1970, state: .preparing)
        guard await persist().value else { record = nil; onChange?(nil); return false }
        return true
    }

    /// Permission or device-open success alone does not prove that any input is arriving.
    func captureDidReceiveInput() {
        guard record?.state == .preparing else { return }
        record?.state = .active
        record?.events.append(SessionLifecycleEvent(kind: "inputReceiving", time: Date().timeIntervalSince1970))
        _ = persist()
    }

    func ingest(who: String, epoch: Int, result: SpeechTranscriptionResult) {
        // A real transcription callback also supplies input evidence if it beats the PCM meter callback.
        if record?.state == .preparing, resumeEpochFloor.map({ epoch > $0 }) ?? true { captureDidReceiveInput() }
        guard let r = record, [.preparing, .active, .finishing].contains(r.state) else { return }
        let id = "\(epoch)-\(who)-\(result.segmentID)"
        let existing = r.utterances.first { $0.id == id }
        if latestIngestEpoch.map({ epoch > $0 }) ?? true {
            latestIngestEpoch = epoch
            currentQuestionID = nil
            currentQuestionOrder = 0
        }
        let currentEpoch = epoch == latestIngestEpoch && (resumeEpochFloor.map { epoch > $0 } ?? true)
        // First receipt orders the segments. A short partial can become eligible
        // later, but cannot overtake a newer eligible segment. A late revision
        // cannot move the question pointer back or reassign an answer
        // (including an answer that initially had no question). This follows
        // receipt order, not semantic turns: overlapping speech or a delayed
        // first transcript may still need user interpretation after the session.
        if who == querySpeaker {
            if questionReceiptOrder[id] == nil {
                nextQuestionOrder += 1
                questionReceiptOrder[id] = nextQuestionOrder
            }
            let acceptedRevision = existing.map { result.revision > ($0.revisions.map(\.revision).max() ?? Int.min) } ?? true
            if currentEpoch, acceptedRevision, SessionQuestionEligibility.isCandidate(result.text),
               let order = questionReceiptOrder[id], order > currentQuestionOrder {
                currentQuestionID = id
                currentQuestionOrder = order
            }
        }
        let questionID: String?
        if let existing {
            questionID = existing.questionID
        } else {
            questionID = who == querySpeaker ? id : (currentEpoch ? currentQuestionID : nil)
        }
        record?.recordUtterance(id: id, who: who,
            revision: SessionTranscriptRevision(revision: result.revision, text: result.text,
                isFinal: result.isFinal, time: Date().timeIntervalSince1970,
                startTime: result.startTime, endTime: result.endTime), questionID: questionID)
        _ = persist()
    }

    @MainActor @discardableResult
    func finish(ears: InterviewEars?, paused: Bool = false, interrupted: Bool = false) async -> Bool {
        if let task = finishingTask { return await task.value }
        guard !busy else { return false }
        guard capturing else { return await flush() }
        busy = true
        let task = Task { @MainActor in
            self.record?.state = .finishing
            _ = self.persist()
            let drained = await ears?.finishEars() ?? true
            self.record?.state = interrupted ? .interrupted : paused ? .paused : .completed
            self.currentQuestionID = nil
            if !paused { self.record?.endedAt = Date().timeIntervalSince1970 }
            self.record?.events.append(SessionLifecycleEvent(kind: drained ? (interrupted ? "captureFailed" : paused ? "paused" : "completed") : "tailIncomplete",
                time: Date().timeIntervalSince1970, detail: drained ? nil : "마지막 전사의 확정을 기다리는 시간이 초과됐습니다. 마지막 수신 내용은 보존했습니다."))
            return await self.persist().value
        }
        finishingTask = task
        let ok = await task.value
        finishingTask = nil
        busy = false
        return ok
    }

    @MainActor func resume() async -> Bool {
        guard !busy, record?.state == .paused else { return false }
        busy = true
        defer { busy = false }
        // Capture restarts with a new epoch. Do not let a drained old-epoch
        // callback establish the question for the resumed capture.
        resumeEpochFloor = latestIngestEpoch
        currentQuestionID = nil
        currentQuestionOrder = 0
        record?.state = .preparing
        record?.events.append(SessionLifecycleEvent(kind: "resumed", time: Date().timeIntervalSince1970))
        return await persist().value
    }

    func retrieval(_ value: SessionRetrieval) {
        guard capturing else { return }
        record?.upsertRetrieval(value)
        _ = persist()
    }

    func event(_ kind: String, detail: String? = nil) {
        guard capturing else { return }
        record?.events.append(SessionLifecycleEvent(kind: kind, time: Date().timeIntervalSince1970, detail: detail))
        _ = persist()
    }

    @MainActor func select(id: String) async {
        guard !capturing, !busy else { return }
        busy = true
        defer { busy = false }
        if reviewTask != nil {
            reviewGeneration += 1
            reviewTask?.cancel(); reviewTask = nil
            record?.analysisStatus = "interrupted"
            record?.analysisMessage = "로컬 제안을 중단했습니다. 다시 제안받을 수 있습니다."
            _ = persist()
        }
        guard await flush() else { return }
        do {
            record = try await store.load(id: id)
            currentQuestionID = nil
            latestIngestEpoch = nil
            resumeEpochFloor = nil
            questionReceiptOrder = [:]
            nextQuestionOrder = 0
            currentQuestionOrder = 0
            onChange?(record)
        }
        catch { onError?(error.localizedDescription) }
    }

    func correct(id: String, text: String) {
        guard !capturing else { return }
        record?.correctUtterance(id: id, text: text, time: Date().timeIntervalSince1970)
        _ = persist()
    }

    @discardableResult
    func setQuestionReview(id: String, status: String) -> Bool {
        guard let snapshot = record, [.completed, .interrupted].contains(snapshot.state),
              status == "open" || status == "done", !id.isEmpty,
              snapshot.utterances.contains(where: { ($0.who == "them" || $0.questionID == $0.id) && $0.id == id }) ||
                snapshot.retrievals.contains(where: { $0.questionID == id || $0.id == id }) else { return false }
        guard snapshot.questionReviews[id] != status else { return true }
        record?.questionReviews[id] = status
        _ = persist()
        return true
    }

    @MainActor @discardableResult
    func setRecordReview(id: String, status: String) async -> Bool {
        guard !busy else {
            onError?("기록 저장이 끝난 뒤 다시 시도해 주세요.")
            return false
        }
        guard let snapshot = record, snapshot.id == id else {
            onError?("선택한 대화 기록을 다시 열고 시도해 주세요.")
            return false
        }
        guard [.completed, .interrupted].contains(snapshot.state) else {
            onError?("사용을 끝낸 뒤 기록을 확인 완료할 수 있습니다.")
            return false
        }
        guard status == "open" || status == "done" else {
            onError?("기록 확인 상태를 바꾸지 못했습니다. 다시 시도해 주세요.")
            return false
        }
        busy = true
        defer { busy = false }
        // Preserve earlier edits and retry an earlier failed completion before
        // accepting another transition or allowing a record switch.
        guard await flush() else { return false }
        pendingRecordReview = (id, status)
        return await persist().value
    }

    func editDraft(_ draft: SessionDraft) {
        guard !capturing, draft.savedAt == nil else { return }
        if let existing = record?.drafts.first(where: { $0.id == draft.id }) {
            guard existing.savedAt == nil, existing.fragmentID == draft.fragmentID else { return }
        }
        record?.upsertDraft(draft)
        _ = persist()
    }

    func markDraft(id: String, path: String?, error: String?) {
        guard var draft = record?.drafts.first(where: { $0.id == id }) else { return }
        draft.error = error
        if error == nil { draft.savedAt = Date().timeIntervalSince1970; draft.relativePath = path }
        record?.upsertDraft(draft)
        _ = persist()
    }

    @MainActor func review() {
        guard let snapshot = record, !capturing, reviewTask == nil else { return }
        record?.analysisStatus = "running"
        record?.analysisMessage = nil
        _ = persist()
        reviewGeneration += 1
        let generation = reviewGeneration
        reviewTask = Task { @MainActor [weak self] in
            let result = await SessionReviewer.suggest(snapshot)
            guard let self, self.reviewGeneration == generation else { return }
            defer { self.reviewTask = nil }
            guard self.record?.id == snapshot.id else { return }
            // The user may have corrected or edited while local inference ran. Never replace those edits.
            if self.record?.utterances != snapshot.utterances || self.record?.drafts != snapshot.drafts {
                self.record?.analysisStatus = "outdated"
                self.record?.analysisMessage = "직접 고친 내용을 유지했습니다. 필요하면 다시 제안받을 수 있습니다."
            } else {
                self.record?.analysisStatus = result.message == nil ? "ready" : "unavailable"
                self.record?.analysisMessage = result.message
                for draft in result.drafts { self.record?.upsertDraft(draft) }
            }
            _ = self.persist()
        }
    }

    /// Returned task includes every preceding write, so finish/quit can wait for disk acknowledgement.
    @discardableResult private func persist() -> Task<Bool, Never> {
        guard var snapshot = record else { return Task { true } }
        let review = pendingRecordReview.flatMap { $0.id == snapshot.id ? $0 : nil }
        if let review { snapshot.reviewStatus = review.status }
        onChange?(record)
        let previous = writing
        let task = Task { @MainActor [weak self, store] in
            _ = await previous?.value
            do {
                try await store.save(snapshot)
                if let self {
                    self.records.removeAll { $0.id == snapshot.id }
                    self.records.insert(snapshot, at: 0)
                    if let review {
                        if self.record?.id == review.id { self.record?.reviewStatus = review.status }
                        if self.pendingRecordReview?.id == review.id,
                           self.pendingRecordReview?.status == review.status {
                            self.pendingRecordReview = nil
                        }
                        self.onChange?(self.record)
                    }
                }
                return true
            } catch {
                self?.onError?("세션 기록을 저장하지 못했습니다. 창을 유지하고 다시 시도해 주세요: \(error.localizedDescription)")
                return false
            }
        }
        writing = task
        return task
    }

    @MainActor func flush() async -> Bool {
        if await writing?.value ?? true { return true }
        return await persist().value
    }
}
