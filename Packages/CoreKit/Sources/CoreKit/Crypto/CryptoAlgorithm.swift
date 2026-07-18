//
//  CryptoAlgorithm.swift
//  ZZFoundation
//
//  Created by xiaoyuan on 2021/10/15.
//

import Foundation
import CommonCrypto

enum CryptoAlgorithm {
    case AES, AES128, DES, DES3, CAST, RC2, RC4, Blowfish
    var algorithm: CCAlgorithm {
        var result: UInt32 = 0
        switch self {
        case .AES:
            result = UInt32(kCCAlgorithmAES)
        case .AES128:
            result = UInt32(kCCAlgorithmAES128)
        case .DES:
            result = UInt32(kCCAlgorithmDES)
        case .DES3:
            result = UInt32(kCCAlgorithm3DES)
        case .CAST:
            result = UInt32(kCCAlgorithmCAST)
        case .RC2:
            result = UInt32(kCCAlgorithmRC2)
        case .RC4:
            result = UInt32(kCCAlgorithmRC4)
        case .Blowfish:
            result = UInt32(kCCAlgorithmBlowfish)
        }
        return CCAlgorithm(result)
    }
    
    var keyLength: Int {
        var result : Int = 0
        switch self {
        case .AES:
            result = kCCKeySizeAES128
        case .AES128:
            result = kCCKeySizeAES256
        case .DES:
            result = kCCKeySizeDES
        case .DES3:
            result = kCCKeySize3DES
        case .CAST:
            result = kCCKeySizeMaxCAST
        case .RC2:
            result = kCCKeySizeMaxRC2
        case .RC4:
            result = kCCKeySizeMaxRC4
        case .Blowfish:
            result = kCCKeySizeMaxBlowfish
        }
        return Int(result)
    }
    
    var cryptLength: Int {
        var result:Int = 0
        switch self {
        case .AES:
            result = kCCKeySizeAES128
        case .AES128:
            result = kCCBlockSizeAES128
        case .DES:
            result = kCCBlockSizeDES
        case .DES3:
            result = kCCBlockSize3DES
        case .CAST:
            result = kCCBlockSizeCAST
        case .RC2:
            result = kCCBlockSizeRC2
        case .RC4:
            result = kCCBlockSizeRC2
        case .Blowfish:
            result = kCCBlockSizeBlowfish
        }
        return Int(result)
    }
    
    // 根据密码创建key
    // password: 生成key的密码
    // salt: 对密码加盐
    static func createKey(password: Data, salt: Data) throws -> Data {
        let length = kCCKeySizeAES256
        var status = Int32(0)
        var derivedBytes = [UInt8](repeating: 0, count: length)
        password.withUnsafeBytes { (passwordBuffer: UnsafeRawBufferPointer) in
            salt.withUnsafeBytes { (saltBuffer: UnsafeRawBufferPointer) in
                let passwordBytes = passwordBuffer.baseAddress?.assumingMemoryBound(to: Int8.self)
                let saltBytes = saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
                status = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes,
                    password.count,
                    saltBytes,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    10000,
                    &derivedBytes,
                    length
                )
            }
        }
        guard status == 0 else {
            // 创建key失败
            throw NSError(domain: NSCocoaErrorDomain, code: Int(status))
        }
        return Data(bytes: derivedBytes, count: length)
    }
    
    static func randomIV() -> Data {
        return randomData(length: kCCBlockSizeAES128)
    }
    
    static func randomSalt() -> Data {
        return randomData(length: 8)
    }
    
    static func randomData(length: Int) -> Data {
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { buffer -> Int32 in
            if let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                return SecRandomCopyBytes(kSecRandomDefault, length, bytes)
            }
            return -1
        }
        assert(status == Int32(0))
        return data
    }
}

extension Data {
    /**
     加密
     - parameter algorithm: 加密算法
     - parameter keyData: 加密key
     - Returns: Data   加密后的数据
     */
    func encrypt(algorithm: CryptoAlgorithm, keyData: Data) -> Data? {
        return crypt(algorithm: algorithm, operation: CCOperation(kCCEncrypt), keyData: keyData)
    }
    
    /// 解密
    /// - Parameters:
    ///   - algorithm: 解密方式
    ///   - keyData: 解密key
    /// - Returns: Data 解密后的数据
    func decrypt(algorithm: CryptoAlgorithm, keyData: Data) -> Data? {
        return crypt(algorithm: algorithm, operation: CCOperation(kCCDecrypt), keyData: keyData)
    }
    
    
    fileprivate func crypt(algorithm: CryptoAlgorithm, operation: CCOperation, keyData: Data) -> Data? {
        let keyBytes = [UInt8](keyData)
        let keyLength = Int(algorithm.keyLength)
        let datalength = self.count
        // data是结构体  使用[UInt8]构造方法得到data的byte数组
        let dataBytes = [UInt8](self)
        ///使用UnsafePointer<UInt8>构造方法生成指针
//        outputStream?.write(UnsafePointer<UInt8>(bytes), maxLength: bytes.count)
        let cryptLength = Int(datalength + algorithm.cryptLength)
        let cryptPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: cryptLength)
        let algoritm = CCAlgorithm(algorithm.algorithm)
        let option = CCOptions(kCCOptionECBMode + kCCOptionPKCS7Padding)
        let numBytesEncrypted = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        numBytesEncrypted.initialize(to: 0)
        let cryptStatus = CCCrypt(operation, algoritm, option, keyBytes, keyLength, nil, dataBytes, datalength, cryptPointer, cryptLength, numBytesEncrypted)
        
        // 判断是否加密成功
        if CCStatus(cryptStatus) == CCStatus(kCCSuccess) {
            let len = Int(numBytesEncrypted.pointee)
            let data = Data(bytes: cryptPointer, count: len)
            numBytesEncrypted.deallocate()
            return data
        } else {
            numBytesEncrypted.deallocate()
            cryptPointer.deallocate()
            return nil
        }
    }
}

extension String {
    /**
     加密
     - parameter algorithm: 加密算法
     - parameter keyData: 加密key
     - Returns: Data   加密后的字符串
     */
    func encrypt(algorithm: CryptoAlgorithm, key: Data) -> String? {
        guard let data = self.data(using: .utf8) else {
            return nil
        }
        guard let encryptData = data.encrypt(algorithm: algorithm, keyData: key) else {
            return nil
        }
        // 加密的结果要用base64转码
        return encryptData.base64EncodedString(options: .endLineWithLineFeed)
    }
    
    func encrypt(algorithm: CryptoAlgorithm, key: String) -> String? {
        guard let keyData = key.data(using: .utf8) else {
            return nil
        }
        return encrypt(algorithm: algorithm, key: keyData)
    }
    
    /**
    解密
    - Parameters:
     - algorithm: 解密方式
     - keyData: 解密key
    - Returns: 解密后的字符串
     */
    func decrypt(algorithm: CryptoAlgorithm, key: Data) -> String? {
        // 将加密后的字符串转换为data
        // 加密后存储是是base64字符串，需要使用base转换为data
        guard let data = Data(base64Encoded: self, options: .ignoreUnknownCharacters) else {
            return nil
        }
        guard let decryptData = data.decrypt(algorithm: algorithm, keyData: key) else {
            return nil
        }
        // 解密结果从data转成string，使用utf8
        return String(data: decryptData, encoding: .utf8)
    }
    
    func decrypt(algorithm: CryptoAlgorithm, key: String) -> String? {
        guard let keyData = key.data(using: .utf8) else {
            return nil
        }
        return decrypt(algorithm: algorithm, key: keyData)
    }
}
