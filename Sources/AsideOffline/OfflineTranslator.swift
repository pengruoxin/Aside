import Foundation
import FoundationModels
import AsideCore

@Generable private struct GeneratedExpression {
    @Guide(description: "One faithful English translation or rewrite, preserving facts and uncertainty.")
    var expression: String
    @Guide(description: "One brief explanation in Simplified Chinese of a useful English expression.")
    var explanation: String
}

@MainActor public enum OfflineTranslator {
    public static var appleAvailable: Bool { SystemLanguageModel.default.isAvailable }
    public static func generate(_ writing: WritingRequest) async throws -> WritingResult {
        guard writing.source.count <= 600 else { throw OfflineError.inputTooLong }
        if OfflineConfiguration.shared.engine == "apple" {
            guard appleAvailable else { throw OfflineError.modelUnavailable }
            let session = LanguageModelSession(instructions: writing.systemPrompt)
            let result = try await session.respond(to: writing.source, generating: GeneratedExpression.self)
            try Task.checkCancellation()
            return try .validated(expression: result.content.expression, explanation: result.content.explanation)
        }
        return try await RuntimeManager.shared.generate(writing)
    }
}
