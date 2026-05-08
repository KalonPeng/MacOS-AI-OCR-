import Foundation
import AppKit

// OCR 配置
struct OCRConfig: Codable {
    // 使用加密的默认 URL（运行时解密）
    var baseURL: String = SensitiveStrings.shared.zhipuOCRBaseURL
    var apiKey: String = ""
    var model: String = "glm-ocr"
    var systemMessage: String = ""  // 智谱 OCR 不需要 system message
    var userMessage: String = ""     // 智谱 OCR 不需要 user message
    
    static func load() -> OCRConfig {
        if let data = UserDefaults.standard.data(forKey: "OCRConfig"),
           let config = try? JSONDecoder().decode(OCRConfig.self, from: data) {
            print("📖 加载配置成功")
            return config
        }
        print("⚠️  未找到配置，使用默认值")
        return OCRConfig()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "OCRConfig")
            UserDefaults.standard.synchronize()
            print("💾 配置保存成功")
        } else {
            print("❌ 配置保存失败")
        }
    }
}

// 智谱 OCR API 响应
struct ZhipuOCRResponse: Codable {
    let data_info: DataInfo?
    let md_results: String?
    let layout_details: [[LayoutDetail]]?
    let error: ErrorInfo?
    
    struct DataInfo: Codable {
        let num_pages: Int?
        let pages: [Page]?
        
        struct Page: Codable {
            let height: Int?
            let width: Int?
        }
    }
    
    struct LayoutDetail: Codable {
        let index: Int?
        let label: String?
        let content: String?  // 元素内容（文本/图片URL/表格HTML）
        let bbox_2d: [Double]?
        let width: Int?
        let height: Int?
    }
    
    struct ErrorInfo: Codable {
        let code: String?
        let message: String?
    }
}

// OCR 服务
class OCRService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastResult: String = ""
    @Published var lastError: String?
    
    // 每次都重新加载配置，确保使用最新的 API 设置
    private var config: OCRConfig {
        return OCRConfig.load()
    }
    
    // 执行 OCR 识别
    func recognize(image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        // 重新加载配置，确保使用最新的 API 设置
        let currentConfig = config
        
        guard !currentConfig.apiKey.isEmpty else {
            let error = NSError(domain: "OCRService", code: -1, userInfo: [NSLocalizedDescriptionKey: "❌ 请先在设置中配置 OCR API Key\n\n点击菜单栏图标 → 设置 → OCR 配置"])
            print("❌ OCR 错误: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        guard URL(string: currentConfig.baseURL) != nil else {
            let error = NSError(domain: "OCRService", code: -1, userInfo: [NSLocalizedDescriptionKey: "❌ API 地址格式错误\n\n请检查设置中的 Base URL 是否正确"])
            print("❌ OCR 错误: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        print("🔍 开始 OCR 识别...")
        
        isProcessing = true
        lastError = nil
        
        // 转换图片为 base64
        guard let base64Image = image.toBase64() else {
            let error = NSError(domain: "OCRService", code: -2, userInfo: [NSLocalizedDescriptionKey: "图片转换失败"])
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastError = error.localizedDescription
                completion(.failure(error))
            }
            return
        }
        
        // 构建请求
        let request: URLRequest
        do {
            request = try self.buildRequest(base64Image: base64Image)
        } catch {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastError = error.localizedDescription
                completion(.failure(error))
            }
            return
        }
        
        // 发送请求
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ 网络请求失败: \(error.localizedDescription)")
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                guard let data = data, let httpResponse = response as? HTTPURLResponse else {
                    let error = NSError(domain: "OCRService", code: -3, userInfo: [NSLocalizedDescriptionKey: "无效的响应"])
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                print("📥 收到响应，状态码: \(httpResponse.statusCode)")
                
                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
                    print("❌ API 错误响应: \(errorMessage)")
                    
                    // 特殊处理：尝试解析 400 错误中的错误码
                    if httpResponse.statusCode == 400 {
                        // 尝试解析错误响应
                        if let errorData = errorMessage.data(using: .utf8),
                           let jsonObject = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                           let error = jsonObject["error"] as? [String: Any],
                           let code = error["code"] as? String {
                            
                            print("📍 错误码: \(code)")
                            
                            // code: 1214 通常表示图片格式或内容问题，可能是空白图片
                            // 这种情况应该当作"未识别到文字"处理，而不是"识别失败"
                            if code == "1214" {
                                print("⚠️ 检测到 code: 1214，判定为未识别到文字")
                                // 返回成功但空字符串，让上层逻辑显示"未识别到文字"
                                self.isProcessing = false
                                self.lastResult = ""
                                completion(.success(""))
                                return
                            }
                        }
                    }
                    
                    var userFriendlyMessage = ""
                    switch httpResponse.statusCode {
                    case 401:
                        userFriendlyMessage = "❌ API Key 无效或已过期\n\n请在设置中检查并更新 API Key"
                    case 403:
                        userFriendlyMessage = "❌ API 访问被拒绝\n\n可能是配额不足或权限问题"
                    case 404:
                        userFriendlyMessage = "❌ API 地址错误\n\n请在设置中检查 Base URL 是否正确"
                    case 429:
                        userFriendlyMessage = "❌ 请求过于频繁\n\n请稍后再试"
                    case 500...599:
                        userFriendlyMessage = "❌ OCR 服务器错误\n\n请稍后再试"
                    default:
                        userFriendlyMessage = "❌ API 返回错误 (状态码: \(httpResponse.statusCode))\n\n\(errorMessage.prefix(100))"
                    }
                    
                    let error = NSError(domain: "OCRService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: userFriendlyMessage])
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                
                // 解析结果
                do {
                    let result = try JSONDecoder().decode(ZhipuOCRResponse.self, from: data)
                    
                    // 检查是否有错误
                    if let error = result.error {
                        print("❌ API 返回错误: \(error.message ?? "未知错误")")
                        let nsError = NSError(domain: "OCRService", code: -5, userInfo: [NSLocalizedDescriptionKey: "OCR 识别失败: \(error.message ?? "未知错误")"])
                        self.isProcessing = false
                        self.lastError = nsError.localizedDescription
                        completion(.failure(nsError))
                        return
                    }
                    
                    // 提取文本内容
                    var text = ""
                    
                    // 优先从 layout_details 中提取文本
                    if let layoutDetails = result.layout_details {
                        let flatDetails = layoutDetails.flatMap { $0 }
                        // 只提取文本和公式类型的内容
                        let textAndFormula = flatDetails.filter { $0.label == "text" || $0.label == "formula" }
                        
                        // 调试：打印所有文本元素
                        print("🔍 layout_details 包含 \(textAndFormula.count) 个文本元素:")
                        for (index, detail) in textAndFormula.enumerated() {
                            let preview = detail.content?.prefix(80) ?? "nil"
                            print("   [\(index)] \(preview)")
                        }
                        
                        // 提取所有文本内容
                        let contents = textAndFormula.compactMap { $0.content }.filter { !$0.isEmpty }
                        text = contents.joined(separator: "\n")
                        
                        print("✅ 从 layout_details 提取文本: \(text.count) 字符")
                    }
                    
                    // 如果 layout_details 为空，使用 md_results 作为后备
                    if text.isEmpty, let mdResults = result.md_results, !mdResults.isEmpty {
                        print("⚠️ layout_details 为空，使用 md_results")
                        text = mdResults
                    }
                    
                    print("✅ 识别成功，文本长度: \(text.count) 字符")
                    print("📝 识别结果预览: \(text.prefix(200))")
                    
                    self.isProcessing = false
                    self.lastResult = text
                    completion(.success(text))
                } catch {
                    print("❌ 解析响应失败: \(error.localizedDescription)")
                    self.isProcessing = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // 构建 API 请求（智谱 OCR 格式）
    private func buildRequest(base64Image: String) throws -> URLRequest {
        guard let url = URL(string: config.baseURL) else {
            throw NSError(domain: "OCRService", code: -4, userInfo: [NSLocalizedDescriptionKey: "无效的 URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60  // OCR 可能需要更长时间
        
        // 智谱 OCR API 需要 data URI 格式的 base64
        let body: [String: Any] = [
            "model": config.model,
            "file": "data:image/png;base64,\(base64Image)",
            "return_crop_images": false,
            "need_layout_visualization": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// NSImage 扩展
extension NSImage {
    func toBase64() -> String? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // 使用 PNG 格式，通用性更好
        guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return imageData.base64EncodedString()
    }
}
