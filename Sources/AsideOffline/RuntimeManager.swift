import Foundation
import AsideCore

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor public final class RuntimeManager {
    public static let shared = RuntimeManager()
    private var process: Process?
    private var startup: Task<(Int, String), Error>?
    private var endpoint: (Int, String)?
    private var lastUsed = Date()
    private var idle: Timer?
    private init() {
        idle = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, Date().timeIntervalSince(self.lastUsed) > 180 else { return }
                self.stop()
            }
        }
    }
    public func stop() {
        startup?.cancel()
        startup = nil
        process?.terminate()
        process = nil
        endpoint = nil
    }
    private func ready() async throws -> (Int, String) {
        lastUsed = Date()
        if let endpoint, process?.isRunning == true { return endpoint }
        if let startup { return try await startup.value }
        let task = Task { @MainActor [weak self] () throws -> (Int, String) in
            guard let self, let model = OfflinePaths.model else { throw OfflineError.modelMissing }
            guard let executable = OfflinePaths.executable else { throw OfflineError.runtimeUnavailable }
            let port = Int.random(in: 20000...60000)
            let key = UUID().uuidString + UUID().uuidString
            let child = Process()
            child.executableURL = executable
            child.arguments = ["--model", model.path, "--host", "127.0.0.1", "--port", String(port), "--ctx-size", "4096",
                               "--parallel", "1", "--threads", "4", "--n-gpu-layers", "99", "--no-webui"]
            child.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LLAMA_API_KEY": key]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            self.process = child
            let session = URLSession(configuration: .ephemeral, delegate: RejectRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            for _ in 0..<150 {
                try Task.checkCancellation()
                guard child.isRunning else { throw OfflineError.startupFailed }
                var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
                request.timeoutInterval = 1
                if let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 {
                    self.endpoint = (port, key)
                    return (port, key)
                }
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            child.terminate()
            throw OfflineError.startupFailed
        }
        startup = task
        do { let result = try await task.value; startup = nil; return result }
        catch { startup = nil; process?.terminate(); process = nil; endpoint = nil; throw error }
    }
    public func generate(_ writing: WritingRequest) async throws -> WritingResult {
        guard writing.source.count <= 600 else { throw OfflineError.inputTooLong }
        let (port, key) = try await ready()
        try Task.checkCancellation()
        var request = URLRequest(url: try OfflineEndpoint.completion(port: port))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "messages": [["role": "system", "content": writing.systemPrompt], ["role": "user", "content": writing.source]],
            "stream": false, "temperature": 0.2, "max_tokens": 1024, "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 128_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else { throw WritingError.invalidResult }
        lastUsed = Date()
        return try WritingResult.parseJSON(text)
    }
}
