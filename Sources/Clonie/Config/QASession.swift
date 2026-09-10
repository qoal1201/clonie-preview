import Foundation
import ClonieCore

enum QASession {
    static let isQABundle = Bundle.main.bundleIdentifier == "com.local.clonie.qa"
    static let current: QASessionConfiguration? = isQABundle
        ? try? QASessionConfiguration(environment: ProcessInfo.processInfo.environment) : nil
}
