/// whisper.cpp 를 남의 바이너리로 불러 wav 한 통을 글자로 바꾼다.
///
/// ⚠ **이 통로는 아직 잠들어 있다** — Swift 는 살아 있는데 부르는 화면이 없다.
///   깨울지는 #63 의 게이트(발화 단위 지연 · #28 실발화 오류율)가 정한다.
/// ★ **그래서 이 파일의 수리는 「깨우면 빈 전사」를 미리 막는 선행 수리다.**
///   `실측 2026-09-01`(#63): 이 파일을 그대로 부르면 45초 대본이 **0글자**로 돌아왔다.
///   실패가 아니라 **빈 문자열**이라, 배선한 날 「마이크가 아무것도 못 들었다」로 보였을 것이다.
///   뿌리 둘 = 아래 `isRealWhisperModel` 과 `transcribe` 의 `--output-file` 주석.
import Foundation

let WHISPER_BIN = "/usr/local/bin/whisper-cli"

func findWhisperBin() -> String? {
    [WHISPER_BIN, "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        .first { FileManager.default.fileExists(atPath: $0) }
}

/// 진짜 모델의 크기 하한. `실측 2026-09-01`: 제일 작은 진짜 모델 tiny 가 **77MB**,
/// base 148MB, small 488MB — brew 의 테스트 픽스처는 **562KB** 다. 사이가 두 자릿수로 벌어져서
/// 이 하한은 흔들릴 자리가 없다.
private let WHISPER_MIN_MODEL_BYTES: Int64 = 10 * 1024 * 1024

/// 이 파일이 「모델」로 인정하는 것. **자물쇠가 둘**이다 — 이름과 크기.
///
/// ⚠ brew 는 `share/whisper-cpp/` **뿌리**에 테스트 픽스처(`for-tests-ggml-tiny.bin`)를 깔고,
///   진짜 모델은 우리가 `models/` 밑에 받는다. 이름만 보면 픽스처도 `ggml` 이 들었다.
/// ⚠ **자물쇠를 하나만 두지 않는 이유**: 이름은 상류가 바꿀 수 있고(그러면 크기가 남는다),
///   크기는 상류가 더 큰 픽스처를 깔면 넘을 수 있다(그러면 이름이 남는다).
private func isRealWhisperModel(_ path: String) -> Bool {
    if (path as NSString).lastPathComponent.contains("for-tests") { return false }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? Int64 else { return false }
    return size >= WHISPER_MIN_MODEL_BYTES
}

/// ⚠ **바퀴가 둘인 것이 이 함수의 전부다.** ① 아는 이름을 **모든 디렉터리에서** 먼저 찾고,
///   ② 그래도 없을 때만 느슨하게 훑는다.
///   한 바퀴로 돌리면 **디렉터리가 이름을 이긴다** — brew 뿌리를 먼저 보다가 거기 있는 아무
///   `ggml*.bin`(=픽스처)을 집고 `models/` 의 진짜 모델엔 닿지도 않는다. `실측 2026-09-01`
///   (#63): 전 판이 정확히 그래서 562KB 픽스처를 골랐고 전사가 0바이트였다.
func findWhisperModel() -> String? {
    let dirs = [
        "/opt/homebrew/share/whisper-cpp",
        "/opt/homebrew/share/whisper-cpp/models",
        "/usr/local/share/whisper-cpp",
        NSHomeDirectory() + "/.cache/whisper",
        NSHomeDirectory() + "/.ollama-chat",
    ]
    /// 앞이 이긴다 = **품질 순위**. `실측 2026-09-01`(#63 A/B, say 3종):
    /// CER small **5.35%** < base 6.91% < SpeechAnalyzer 8.15%, 핵심어 생존도 small 이 제일 낫다.
    /// ⚠ `.en` 은 **영어 전용이라 한국어를 한 글자도 못 적는다** — 다른 것이 하나도 없을 때의
    ///   마지막 자리다. 전 판은 이걸 **1순위**에 뒀다(이 제품은 ko-KR 이다).
    let preferred = ["ggml-small.bin", "ggml-base.bin", "ggml-medium.bin",
                     "ggml-tiny.bin", "ggml-base.en.bin"]
    for dir in dirs {
        for name in preferred {
            let p = dir + "/" + name
            if FileManager.default.fileExists(atPath: p), isRealWhisperModel(p) { return p }
        }
    }
    for dir in dirs {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
        // ⚠ `sorted()` 가 있어야 **결정적**이다 — `contentsOfDirectory` 는 순서를 약속하지 않는다.
        //   순서가 흔들리면 「어제는 되던 것이 오늘 다른 모델을 집는」 모양이 난다.
        if let m = files.sorted().first(where: {
            $0.hasSuffix(".bin") && $0.contains("ggml") && isRealWhisperModel(dir + "/" + $0)
        }) {
            return dir + "/" + m
        }
    }
    return nil
}

func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
    guard let bin   = findWhisperBin(),
          let model = findWhisperModel() else { completion(nil); return }
    print("[whisper] \(bin) model=\(model)")

    // ★ **쓰는 자리와 읽는 자리가 한 값에서 나온다.** `--output-txt` 는 기본으로
    //   **입력 경로 뒤에 그냥 `.txt` 를 붙인다** — `a.wav` → `a.wav.txt`. 아래 읽는 자리는
    //   확장자를 갈아낀 `a.txt` 를 봤고, 그래서 파일 경로가 **항상 빗나가** 타임스탬프가 섞인
    //   stdout 폴백으로만 돌았다 (`실측 2026-09-01`, #63 — 덤으로 `a.wav.txt` 가 매번 남았다).
    //   `--output-file`(확장자 **없는** 기준 이름)로 못을 박아 둘이 갈릴 수 없게 한다.
    let txtBase = audioURL.deletingPathExtension().path
    let txtURL  = URL(fileURLWithPath: txtBase + ".txt")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    // ⚠ `--no-timestamps` 는 **폴백을 위한 것**이다 — txt 파일엔 원래 타임스탬프가 안 들어간다
    //   (`실측 2026-09-01`). 파일 경로가 살아난 지금 아래 정규식이 걷을 것은 없고, 이 깃발은
    //   그래도 폴백으로 내려갔을 때 stdout 이 맨 글자이게 한다.
    // ⚠ `--language auto` 는 아직 안 정해진 자리다. #63 하네스는 `-l ko` 로 쟀고,
    //   `실측 2026-09-01`: 5초 조각에서 auto 가 **+0.15초**(0.84 vs 0.69), 글자는 같았다.
    //   배선할 때 #63 이 정한다.
    task.arguments = ["--model", model, "--language", "auto",
                      "--output-txt", "--output-file", txtBase,
                      "--no-timestamps", "--no-prints",
                      "--file", audioURL.path]
    let pipe = Pipe()
    task.standardOutput = pipe; task.standardError = Pipe()
    task.terminationHandler = { _ in
        if let text = try? String(contentsOf: txtURL, encoding: .utf8) {
            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: txtURL)
            try? FileManager.default.removeItem(at: audioURL)
            completion(cleaned.isEmpty ? nil : cleaned)
        } else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: audioURL)
            completion(text.isEmpty ? nil : text)
        }
    }
    do { try task.run() } catch { print("[whisper] \(error)"); completion(nil) }
}
