import Foundation
import GhostbarCore

enum QASession {
    static let isQABundle = Bundle.main.bundleIdentifier == "com.local.ghostbar.qa"
    static let current: QASessionConfiguration? = isQABundle
        ? try? QASessionConfiguration(environment: ProcessInfo.processInfo.environment) : nil
}
