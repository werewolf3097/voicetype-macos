#!/bin/bash
set -euo pipefail

# Бенчмарк 20 запросов к домашнему шлюзу в режиме «Авто» на русской фразе ~5 с.
# Токен берётся исключительно из переменной окружения VOICE_GATEWAY_TOKEN
# и никогда не выводится в stdout/stderr. Текст диктовки также не печатается.
#
# Использование:
#   VOICE_GATEWAY_TOKEN="..." bash VoiceType/scripts/benchmark-gateway.sh
#   VOICE_GATEWAY_TOKEN="..." VOICE_GATEWAY_URL="http://100.79.78.37:8790" bash VoiceType/scripts/benchmark-gateway.sh [path/to/phrase.wav]

if [ -z "${VOICE_GATEWAY_TOKEN:-}" ]; then
  echo "Ошибка: задайте переменную окружения VOICE_GATEWAY_TOKEN." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_DIR="$ROOT_DIR/VoiceType/Sources"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

WAV_PATH="${1:-}"
if [ -z "$WAV_PATH" ]; then
  WAV_PATH="$TMP_DIR/ru_phrase_5s.wav"
  say -v Milena -o "$WAV_PATH" --data-format=LEI16@16000 \
    "Привет, это тестовая проверка скорости распознавания русской речи через домашний сервер в режиме авто."
fi

cat << 'EOF' > "$TMP_DIR/main.swift"
import Foundation

@main
struct GatewayBenchmark {
    static func main() async throws {
        guard let token = ProcessInfo.processInfo.environment["VOICE_GATEWAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            fputs("VOICE_GATEWAY_TOKEN is missing\n", stderr)
            exit(1)
        }
        let baseURL = ProcessInfo.processInfo.environment["VOICE_GATEWAY_URL"] ?? HomeServerConfig.defaultURLString
        let runs = Int(ProcessInfo.processInfo.environment["BENCH_RUNS"] ?? "20") ?? 20
        guard CommandLine.arguments.count >= 2 else {
            fputs("Usage: benchmark <wav_path>\n", stderr)
            exit(1)
        }
        let wavURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let wavSize = ((try? FileManager.default.attributesOfItem(atPath: wavURL.path)[.size]) as? NSNumber)?.intValue ?? 0

        let compressor = AudioCompressor()
        let sampleCompressed = try compressor.compressForGateway(fileURL: wavURL)
        print("Input WAV: \(wavSize) B -> \(sampleCompressed.codecName): \(sampleCompressed.outputBytes) B (encode sample: \(sampleCompressed.encodingMs) ms)")

        let provider = HomeServerProvider(
            config: HomeServerConfig(
                baseURLString: baseURL,
                token: token,
                engine: .auto,
                language: .ru
            ),
            compressor: compressor
        )

        let health = try await provider.checkHealth()
        print("Health: ok=\(health.ok) latencyMs=\(health.latencyMs) engines=\(health.availableEngines.joined(separator: ","))")

        var totalLatencies: [Int] = []
        var enginesCount: [String: Int] = [:]

        for idx in 1...runs {
            let started = CFAbsoluteTimeGetCurrent()
            let result = try await provider.transcribe(fileURL: wavURL)
            let elapsedMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - started) * 1000).rounded()))
            totalLatencies.append(elapsedMs)
            enginesCount[result.engine, default: 0] += 1
            print(String(format: "#%02d engine=%@ lang=%@ total=%dms textChars=%d",
                         idx,
                         result.engine,
                         result.languageCode ?? "-",
                         elapsedMs,
                         result.text.count))
        }

        let sorted = totalLatencies.sorted()
        let p50 = sorted[Int(Double(sorted.count - 1) * 0.50)]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let minMs = sorted.first ?? 0
        let maxMs = sorted.last ?? 0
        let avgMs = Int((Double(sorted.reduce(0, +)) / Double(max(1, sorted.count))).rounded())

        print("--- Summary (n=\(runs), engine=auto, lang=ru) ---")
        print("p50=\(p50) ms | p95=\(p95) ms | avg=\(avgMs) ms | min=\(minMs) ms | max=\(maxMs) ms")
        print("engines=\(enginesCount)")
    }
}
EOF

swiftc -O -parse-as-library \
  "$TMP_DIR/main.swift" \
  "$SOURCES_DIR/AudioCompressor.swift" \
  "$SOURCES_DIR/TranscriptionProvider.swift" \
  "$SOURCES_DIR/HomeServerProvider.swift" \
  "$SOURCES_DIR/GapiClient.swift" \
  "$SOURCES_DIR/RussianTransliterator.swift" \
  "$SOURCES_DIR/TranscriptionProgress.swift" \
  -o "$TMP_DIR/gateway-bench"

"$TMP_DIR/gateway-bench" "$WAV_PATH"
