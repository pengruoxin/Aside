import Foundation

public enum OfflineEndpoint {
    public static func completion(port: Int) throws -> URL {
        guard (1024...65535).contains(port), let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw OfflineError.runtimeUnavailable
        }
        return url
    }
}

public enum OfflineError: LocalizedError {
    case modelMissing, runtimeUnavailable, modelUnavailable, startupFailed, inputTooLong
    public var errorDescription: String? {
        switch self {
        case .modelMissing: return "未找到离线语言包，请安装完整版或在输入法设置中导入 GGUF。打字仍可正常使用。"
        case .runtimeUnavailable: return "离线推理程序不可用，请重新安装完整版句外输入法。"
        case .modelUnavailable: return "苹果本机模型暂不可用，请切换到包内离线语言包。"
        case .startupFailed: return "本机模型未能启动；可稍后重试或在输入法设置检查离线包。"
        case .inputTooLong: return "当前内容较长，请按一句话处理；原文不会被截断。"
        }
    }
}
