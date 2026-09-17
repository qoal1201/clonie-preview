import Foundation

/// The live retrieval input's existing length/filler gate, not semantic
/// question classification or a retrieval-quality threshold.
public enum SessionQuestionEligibility {
    private static let fillers: Set<String> = [
        "네", "넹", "넵", "예", "응", "음", "어", "아", "오", "그", "뭐",
        "네네", "예예", "어어", "음음", "아아", "그래", "그래요", "그렇죠", "그쵸", "그렇군요", "그렇습니다",
        "알겠습니다", "알겠어요", "좋습니다", "좋아요", "맞아요", "맞습니다", "오케이", "감사합니다", "고맙습니다"
    ]

    public static func isCandidate(_ text: String) -> Bool {
        TranscriptText.forSearch(text).split(whereSeparator: { $0.isWhitespace })
            .filter { !fillers.contains(String($0)) }.joined().utf16.count >= 5
    }
}

/// A recorded conversation's lifecycle.
public enum SessionState: String, Codable, Equatable, Sendable {
    case preparing
    case active
    case paused
    case finishing
    case completed
    case interrupted
}

/// One revision emitted by the transcription engine for an utterance.
public struct SessionTranscriptRevision: Codable, Equatable, Sendable {
    public var revision: Int
    public var text: String
    public var isFinal: Bool
    public var time: Double
    public var startTime: Double?
    public var endTime: Double?

    public init(revision: Int, text: String, isFinal: Bool, time: Double,
                startTime: Double? = nil, endTime: Double? = nil) {
        self.revision = revision
        self.text = text
        self.isFinal = isFinal
        self.time = time
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// A speaker's utterance, including the raw transcription history and any
/// later user corrections.
public struct SessionUtterance: Codable, Equatable, Sendable {
    public var id: String
    public var who: String
    public var revisions: [SessionTranscriptRevision]
    public var corrections: [SessionCorrection]
    public var questionID: String?

    public init(id: String, who: String,
                revisions: [SessionTranscriptRevision] = [],
                corrections: [SessionCorrection] = [], questionID: String? = nil) {
        self.id = id
        self.who = who
        self.revisions = revisions
        self.corrections = corrections
        self.questionID = questionID
    }

    /// The most recent raw transcript according to the engine's revision
    /// number. Corrections remain separate from this value on disk.
    public var originalText: String {
        revisions.max { left, right in left.revision < right.revision }?.text ?? ""
    }

    /// The last non-empty user correction, or the most recent raw transcript.
    public var text: String {
        corrections.last?.text ?? originalText
    }
}

public struct SessionCorrection: Codable, Equatable, Sendable {
    public var text: String
    public var time: Double

    public init(text: String, time: Double) {
        self.text = text
        self.time = time
    }
}

public struct SessionCandidate: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    public var excerpt: String
    public var score: Double

    public init(id: String, title: String, path: String, excerpt: String, score: Double) {
        self.id = id
        self.title = title
        self.path = path
        self.excerpt = excerpt
        self.score = score
    }
}

public struct SessionRetrieval: Codable, Equatable, Sendable {
    public var id: String
    public var query: String
    public var scope: String
    public var questionID: String?
    public var requestedAt: Double
    public var completedAt: Double?
    public var candidates: [SessionCandidate]
    public var error: String?
    /// Retrieval computation and displayed material, not a quality judgment.
    public var status: String?
    public var displayedID: String?
    public var displayMode: String?
    /// Search method that produced the visible candidates; absent in older records.
    public var how: String?

    public init(id: String, query: String, scope: String, questionID: String? = nil,
                requestedAt: Double, completedAt: Double? = nil,
                candidates: [SessionCandidate] = [], error: String? = nil,
                status: String? = nil, displayedID: String? = nil, displayMode: String? = nil,
                how: String? = nil) {
        self.id = id
        self.query = query
        self.scope = scope
        self.questionID = questionID
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.candidates = candidates
        self.error = error
        self.status = status
        self.displayedID = displayedID
        self.displayMode = displayMode
        self.how = how
    }
}

public struct SessionDraft: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var fragmentID: String
    public var relativePath: String?
    public var sourceIDs: [String]
    public var savedAt: Double?
    public var error: String?

    public init(id: String, title: String, body: String, fragmentID: String,
                relativePath: String? = nil, sourceIDs: [String] = [],
                savedAt: Double? = nil, error: String? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.fragmentID = fragmentID
        self.relativePath = relativePath
        self.sourceIDs = sourceIDs
        self.savedAt = savedAt
        self.error = error
    }
}

public struct SessionLifecycleEvent: Codable, Equatable, Sendable {
    public var kind: String
    public var time: Double
    public var detail: String?

    public init(kind: String, time: Double, detail: String? = nil) {
        self.kind = kind
        self.time = time
        self.detail = detail
    }
}

/// The durable record for one recording session.
public struct SessionRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: String
    public var vaultPath: String
    public var startedAt: Double
    public var endedAt: Double?
    public var state: SessionState
    /// Whole-record review, separate from capture lifecycle. Missing means open.
    public var reviewStatus: String?
    public var utterances: [SessionUtterance]
    public var retrievals: [SessionRetrieval]
    /// Explicit user review state keyed by question ID; absent entries remain open.
    public var questionReviews: [String: String]
    public var drafts: [SessionDraft]
    public var analysisStatus: String
    public var analysisMessage: String?
    public var events: [SessionLifecycleEvent]

    public init(schemaVersion: Int = SessionRecord.currentSchemaVersion,
                id: String = UUID().uuidString.lowercased(), vaultPath: String,
                startedAt: Double, endedAt: Double? = nil, state: SessionState,
                utterances: [SessionUtterance] = [], retrievals: [SessionRetrieval] = [],
                drafts: [SessionDraft] = [], analysisStatus: String = "notStarted",
                analysisMessage: String? = nil, events: [SessionLifecycleEvent] = [],
                questionReviews: [String: String] = [:], reviewStatus: String? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.vaultPath = vaultPath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.state = state
        self.reviewStatus = reviewStatus
        self.utterances = utterances
        self.retrievals = retrievals
        self.questionReviews = questionReviews
        self.drafts = drafts
        self.analysisStatus = analysisStatus
        self.analysisMessage = analysisMessage
        self.events = events
    }

    /// Records a newer transcript revision while retaining every accepted raw
    /// revision. Revisions with an already-seen or lower number are ignored.
    public mutating func recordUtterance(id: String, who: String,
                                         revision: SessionTranscriptRevision,
                                         questionID: String? = nil) {
        guard let index = utterances.firstIndex(where: { $0.id == id }) else {
            utterances.append(SessionUtterance(id: id, who: who, revisions: [revision],
                                               questionID: questionID))
            return
        }

        guard !utterances[index].revisions.contains(where: { $0.revision == revision.revision }),
              revision.revision > (utterances[index].revisions.map(\.revision).max() ?? Int.min)
        else {
            return
        }

        utterances[index].revisions.append(revision)
        if utterances[index].questionID == nil, let questionID {
            utterances[index].questionID = questionID
        }
    }

    /// Adds a correction only when it contains non-whitespace text.
    @discardableResult
    public mutating func correctUtterance(id: String, text: String, time: Double) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let index = utterances.firstIndex(where: { $0.id == id }) else {
            return false
        }
        utterances[index].corrections.append(SessionCorrection(text: text, time: time))
        return true
    }

    public mutating func upsertRetrieval(_ retrieval: SessionRetrieval) {
        if let index = retrievals.firstIndex(where: { $0.id == retrieval.id }) {
            retrievals[index] = retrieval
        } else {
            retrievals.append(retrieval)
        }
    }

    public mutating func upsertDraft(_ draft: SessionDraft) {
        if let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
        } else {
            drafts.append(draft)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, vaultPath, startedAt, endedAt, state, reviewStatus
        case utterances, retrievals, drafts, analysisStatus, analysisMessage, events, questionReviews
    }

    /// Decoding is strict about the schema version so a future app cannot be
    /// silently rewritten by this version. New optional metadata can still be
    /// read with the defaults used by the public initializer.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: container,
                debugDescription: "Unsupported session schema version: \(schemaVersion)")
        }

        self.schemaVersion = schemaVersion
        self.id = try container.decode(String.self, forKey: .id)
        self.vaultPath = try container.decode(String.self, forKey: .vaultPath)
        self.startedAt = try container.decode(Double.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(Double.self, forKey: .endedAt)
        self.state = try container.decode(SessionState.self, forKey: .state)
        self.reviewStatus = try container.decodeIfPresent(String.self, forKey: .reviewStatus)
        self.utterances = try container.decodeIfPresent([SessionUtterance].self, forKey: .utterances) ?? []
        self.retrievals = try container.decodeIfPresent([SessionRetrieval].self, forKey: .retrievals) ?? []
        self.questionReviews = try container.decodeIfPresent([String: String].self, forKey: .questionReviews) ?? [:]
        self.drafts = try container.decodeIfPresent([SessionDraft].self, forKey: .drafts) ?? []
        self.analysisStatus = try container.decodeIfPresent(String.self, forKey: .analysisStatus) ?? "notStarted"
        self.analysisMessage = try container.decodeIfPresent(String.self, forKey: .analysisMessage)
        self.events = try container.decodeIfPresent([SessionLifecycleEvent].self, forKey: .events) ?? []
    }
}
