import Foundation
import CryptoKit

// MARK: - 字符串加密工具
/// 用于加密敏感信息，防止静态分析直接获取明文
final class StringEncryption {
    
    // 单例
    static let shared = StringEncryption()
    
    // 私有初始化
    private init() {}
    
    // MARK: - XOR 加密/解密
    /// 使用 XOR 加密字符串（对称加密，加密和解密使用相同方法）
    /// - Parameters:
    ///   - string: 要加密/解密的字符串
    ///   - key: 加密密钥
    /// - Returns: 加密/解密后的字符串
    func xorEncrypt(_ string: String, key: String) -> String {
        guard !string.isEmpty, !key.isEmpty else { return string }
        
        let stringBytes = Array(string.utf8)
        let keyBytes = Array(key.utf8)
        var result = [UInt8]()
        
        for (index, byte) in stringBytes.enumerated() {
            let keyByte = keyBytes[index % keyBytes.count]
            result.append(byte ^ keyByte)
        }
        
        return Data(result).base64EncodedString()
    }
    
    /// 解密 XOR 加密的字符串
    func xorDecrypt(_ encrypted: String, key: String) -> String {
        guard !encrypted.isEmpty, !key.isEmpty else { return encrypted }
        
        guard let data = Data(base64Encoded: encrypted) else { return encrypted }
        
        let encryptedBytes = Array(data)
        let keyBytes = Array(key.utf8)
        var result = [UInt8]()
        
        for (index, byte) in encryptedBytes.enumerated() {
            let keyByte = keyBytes[index % keyBytes.count]
            result.append(byte ^ keyByte)
        }
        
        return String(bytes: result, encoding: .utf8) ?? encrypted
    }
    
    // MARK: - AES 加密/解密 (更安全)
    /// 使用 AES-GCM 加密字符串
    func aesEncrypt(_ string: String, key: String) -> String? {
        guard !string.isEmpty else { return nil }
        
        // 从密钥字符串生成 256 位密钥
        let keyData = SHA256.hash(data: Data(key.utf8))
        let symmetricKey = SymmetricKey(data: keyData)
        
        guard let data = string.data(using: .utf8) else { return nil }
        
        do {
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            return sealedBox.combined?.base64EncodedString()
        } catch {
            print("⚠️ AES 加密失败: \(error)")
            return nil
        }
    }
    
    /// 解密 AES-GCM 加密的字符串
    func aesDecrypt(_ encrypted: String, key: String) -> String? {
        guard !encrypted.isEmpty else { return nil }
        
        guard let data = Data(base64Encoded: encrypted) else { return nil }
        
        // 从密钥字符串生成 256 位密钥
        let keyData = SHA256.hash(data: Data(key.utf8))
        let symmetricKey = SymmetricKey(data: keyData)
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            print("⚠️ AES 解密失败: \(error)")
            return nil
        }
    }
}

// MARK: - 敏感字符串管理器
/// 统一管理应用中的敏感字符串，运行时动态解密
final class SensitiveStrings {
    
    static let shared = SensitiveStrings()
    
    // 加密密钥 - 使用设备相关信息和随机字符串组合
    private var encryptionKey: String {
        // 组合多个因素生成密钥，增加破解难度
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ocr.cbd"
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let salt = "0CR_C8D_S@lt_K3y_2024"
        return "\(bundleID).\(version).\(salt)"
    }
    
    private init() {}
    
    // MARK: - 预加密的敏感字符串
    // 使用 XOR 加密，密钥基于 bundleID + version + salt
    
    // 智谱 OCR API 默认地址 (加密存储)
    private let encryptedZhipuOCRURL = "CxsZXhxZXUwNFEsPXhJHUl1BVCY+cSBWaz4jKUMEPipAVikGH15VGgAYWjATExERDUAG"
    
    // DeepSeek API 示例地址 (加密存储)
    private let encryptedDeepSeekURL = "CxsZXhxZXUwDFEdPFBVLRUNLVSh8PCxVazw7IRhbPCReCTNXRFtbDRw="
    
    // MARK: - 获取解密后的字符串
    
    /// 获取智谱 OCR API 默认地址
    var zhipuOCRBaseURL: String {
        return StringEncryption.shared.xorDecrypt(encryptedZhipuOCRURL, key: encryptionKey)
    }
    
    /// 获取 DeepSeek API 示例地址
    var deepSeekExampleURL: String {
        return StringEncryption.shared.xorDecrypt(encryptedDeepSeekURL, key: encryptionKey)
    }
    
    // MARK: - 工具方法（开发时使用）
    
    /// 加密字符串（开发时使用，生成加密后的值替换上面的常量）
    func encrypt(_ plainText: String) -> String {
        return StringEncryption.shared.xorEncrypt(plainText, key: encryptionKey)
    }
    
    /// 解密字符串
    func decrypt(_ encrypted: String) -> String {
        return StringEncryption.shared.xorDecrypt(encrypted, key: encryptionKey)
    }
    
    #if DEBUG
    /// 打印加密结果（仅调试模式可用）
    func printEncrypted(_ plainText: String) {
        let encrypted = encrypt(plainText)
        print("🔐 原文: \(plainText)")
        print("🔒 密文: \(encrypted)")
        print("🔓 验证: \(decrypt(encrypted))")
    }
    #endif
}

// MARK: - String 扩展
extension String {
    
    /// 字符串混淆 - 将字符串拆分存储，运行时拼接
    /// 用于保护那些不方便加密的短字符串
    static func obfuscated(_ parts: String...) -> String {
        return parts.joined()
    }
    
    /// Base64 编码
    var base64Encoded: String? {
        return data(using: .utf8)?.base64EncodedString()
    }
    
    /// Base64 解码
    var base64Decoded: String? {
        guard let data = Data(base64Encoded: self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - 安全存储扩展
extension UserDefaults {
    
    /// 安全存储字符串（加密后存储）
    func setSecure(_ value: String, forKey key: String) {
        if let encrypted = StringEncryption.shared.aesEncrypt(value, key: secureKey(for: key)) {
            set(encrypted, forKey: key)
        }
    }
    
    /// 获取安全存储的字符串（自动解密）
    func secureString(forKey key: String) -> String? {
        guard let encrypted = string(forKey: key) else { return nil }
        return StringEncryption.shared.aesDecrypt(encrypted, key: secureKey(for: key))
    }
    
    private func secureKey(for key: String) -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ocr.cbd"
        return "\(bundleID).\(key).secure"
    }
}
