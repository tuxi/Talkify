//
//  RSA.swift
//  CryptoSwiftDemo
//
//  Created by xiaoyuan on 2022/3/22.
//

import Foundation
import Security

private func debugLog<T>(_ message: T, fileName: String = #file, methodName: String = #function, lineNumber: Int = #line)
{
    
#if DEBUG
    let fName = ((fileName as NSString).pathComponents.last!)
    let log = "\(fName).\(methodName)[\(lineNumber)]: \(message)"
    print(log)
    
#endif
}


public struct RSA {
    // MARK:-  encrypt or decrypt by SecKey String
    
    /// 使用私钥字符串加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - privateKey: 私钥字符串
    /// - Returns: 加密后Data
    public static func encryptData(_ data: Data, privateKey: String) -> Data? {
        guard let secKey = addPrivateKey(privateKey) else {
            return nil
        }
        return encrypt(data, with: secKey, and: true)
    }
    
    /// 使用私钥字符串加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - privateKey: 私钥字符串
    /// - Returns: 加密后String
    public static func encryptString(_ string: String, privateKey: String) -> String? {
        guard let data = encryptData(string.data(using: .utf8)!, privateKey: privateKey) else {
            return nil
        }
        return base64EncodeData(data)
    }
    
    /// 使用私钥字符串解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - privateKey: 私钥字符串
    /// - Returns: 解密后Data
    public static func decryptData(_ data: Data, privateKey: String) -> Data? {
        guard let secKey = addPrivateKey(privateKey) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 使用私钥字符串解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - privateKey: 私钥字符串
    /// - Returns: 解密后String
    public static func decryptString(_ string: String, privateKey: String) -> String? {
        guard let data = base64Decode(string) else {
            return nil
        }
        guard let data = decryptData(data, privateKey: privateKey) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    /// 使用公钥字符串加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - publicKey: 公钥字符串
    /// - Returns: 加密后Data
    public static func encryptData(_ data: Data, publicKey: String) -> Data? {
        guard let secKey = addPublicKey(publicKey) else {
            debugLog("加密失败, 结果为空: addPublicKey(publicKey)")
            return nil
        }
        return encrypt(data, with: secKey, and: false)
    }
    
    /// 使用公钥字符串加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - publicKey: 公钥字符串
    /// - Returns: 加密后String
    public static func encryptString(_ string: String, publicKey: String) -> String? {
        debugLog("需加密的String: \(string) publicKey: \(publicKey)")
        guard let data = string.data(using: .utf8) else {
            debugLog("加密失败, 结果为空: string.data")
            return nil
        }
        guard let data = encryptData(data, publicKey: publicKey) else {
            debugLog("加密失败, 结果为空: encryptData(str, publicKey")
            return nil
        }
        let result = base64EncodeData(data)
        debugLog("加密后的字符串为：\(result)")
        return result
    }
    
    /// 使用公钥字符串解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - publicKey: 公钥字符串
    /// - Returns: 解密后Data
    public static func decryptData(_ data: Data, publicKey: String) -> Data? {
        guard let secKey = addPublicKey(publicKey) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 使用公钥字符串解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - publicKey: 公钥字符串
    /// - Returns: 解密后String
    public static func decryptString(_ string: String, publicKey: String) -> String? {
        guard let data = base64Decode(string),
              let data = decryptData(data, publicKey: publicKey) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    //MARK:- encrypt or decrypt by SecKey data
    
    /// 使用私钥Data加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - privateKeyData: 私钥Data
    /// - Returns: 加密后的Data
    public static func encryptData(_ data: Data, privateKeyData: Data) -> Data? {
        guard let secKey = addPrivateKey(privateKeyData) else {
            return nil
        }
        return encrypt(data, with: secKey, and: true)
    }
    
    /// 使用私钥Data加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - privateKeyData: 私钥Data
    /// - Returns: 加密后的String
    public static func encryptString(_ string: String, privateKeyData: Data) -> String? {
        guard let str = string.data(using: .utf8),
              let data = encryptData(str, privateKeyData: privateKeyData) else {
            return nil
        }
        return base64EncodeData(data)
    }
    
    /// 用私钥Data解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - privateKeyData: 私钥Data
    /// - Returns: 解密后的Data
    public static func decryptData(_ data: Data, privateKeyData: Data) -> Data? {
        guard let secKey = addPrivateKey(privateKeyData) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 用私钥Data解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - privateKeyData: 私钥Data
    /// - Returns: 解密后的String
    public static func decryptString(_ string: String, privateKeyData: Data) -> String? {
        guard let data = base64Decode(string),
              let data = decryptData(data, privateKeyData: privateKeyData) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    /// 使用公钥Data加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - publicKeyData: 公钥Data
    /// - Returns: 加密后Data
    public static func encryptData(_ data: Data, publicKeyData: Data) -> Data? {
        guard let secKey = addPublicKey(publicKeyData) else {
            return nil
        }
        return encrypt(data, with: secKey, and: false)
    }
    
    /// 使用公钥Data加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - publicKeyData: 公钥Data
    /// - Returns: 加密后String
    public static func encryptString(_ string: String, publicKeyData: Data) -> String? {
        guard let str = string.data(using: .utf8),
              let data = encryptData(str, publicKeyData: publicKeyData) else {
            return nil
        }
        return base64EncodeData(data)
    }
    
    /// 使用公钥Data解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - publicKeyData: 公钥Data
    /// - Returns: 解密后Data
    public static func decryptData(_ data: Data, publicKeyData: Data) -> Data? {
        guard let secKey = addPublicKey(publicKeyData) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 使用公钥Data解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - publicKeyData: 公钥Data
    /// - Returns: 解密后String
    public static func decryptString(_ string: String, publicKeyData: Data) -> String? {
        guard let data = base64Decode(string),
              let data = decryptData(data, publicKeyData: publicKeyData) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    //MARK:- encrypt or decrypt by SecKey path
    
    
    /// 使用私钥证书路径加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - privateKeyPath: 私钥证书路径
    /// - Returns: 加密后Data
    public static func encryptData(_ data: Data, privateKeyPath: String) -> Data? {
        guard let secKey = loadPrivateKey(privateKeyPath) else {
            return nil
        }
        return encrypt(data, with: secKey, and: true)
    }
    
    /// 使用私钥证书路径加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - privateKeyPath: 私钥证书路径
    /// - Returns: 加密后String
    public static func encryptString(_ string: String, privateKeyPath: String) -> String? {
        guard let str = string.data(using: .utf8),
              let data = encryptData(str, privateKeyPath: privateKeyPath) else {
            return nil
        }
        return base64EncodeData(data)
    }
    
    /// 使用私钥证书路径解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - privateKeyPath: 私钥证书路径
    /// - Returns: 解密后Data
    public static func decryptData(_ data: Data, privateKeyPath: String) -> Data? {
        guard let secKey = loadPrivateKey(privateKeyPath) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 使用私钥证书路径解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - privateKeyPath: 私钥证书路径
    /// - Returns: 解密后String
    public static func decryptString(_ string: String, privateKeyPath: String) -> String? {
        guard let data = base64Decode(string),
              let data = decryptData(data, privateKeyPath: privateKeyPath) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    /// 使用公钥证书路径加密Data
    /// - Parameters:
    ///   - data: 需加密的Data
    ///   - publicKeyPath: 公钥证书路径
    /// - Returns: 加密后Data
    public static func encryptData(_ data: Data, publicKeyPath: String) -> Data? {
        guard let secKey = loadPublicKey(publicKeyPath) else {
            return nil
        }
        return encrypt(data, with: secKey, and: false)
    }
    
    /// 使用公钥证书路径加密String
    /// - Parameters:
    ///   - string: 需加密的String
    ///   - publicKeyPath: 公钥证书路径
    /// - Returns: 加密后String
    public static func encryptString(_ string: String, publicKeyPath: String) -> String? {
        guard let str = string.data(using: .utf8),
              let data = encryptData(str, publicKeyPath: publicKeyPath) else {
            return nil
        }
        return base64EncodeData(data)
    }
    
    /// 使用公钥证书路径解密Data
    /// - Parameters:
    ///   - data: 需解密的Data
    ///   - publicKeyPath: 公钥证书路径
    /// - Returns: 解密后Data
    public static func decryptData(_ data: Data, publicKeyPath: String) -> Data? {
        guard let secKey = loadPublicKey(publicKeyPath) else {
            return nil
        }
        return decrypt(data, with: secKey)
    }
    
    /// 使用公钥证书路径解密String
    /// - Parameters:
    ///   - string: 需解密的String
    ///   - publicKeyPath: 公钥证书路径
    /// - Returns: 解密后String
    public static func decryptString(_ string: String, publicKeyPath: String) -> String? {
        guard let data = base64Decode(string),
              let data = decryptData(data, publicKeyPath: publicKeyPath) else {
            return nil
        }
        return String.init(data: data, encoding: .utf8)
    }
    
    
    //MARK:- OTHER
    
    private static func base64EncodeData(_ data: Data) -> String? {
        //    NSDataBase64Encoding64CharacterLineLength: 作用是将生成的Base64字符串按照64个字符长度进行等分换行。
        //    NSDataBase64Encoding76CharacterLineLength：作用是将生成的Base64字符串按照76个字符长度进行等分换行。
        //    NSDataBase64EncodingEndLineWithCarriageReturn：作用是将生成的Base64字符串以回车结束。
        //    NSDataBase64EncodingEndLineWithLineFeed：作用是将生成的Base64字符串以换行结束
        let newData = data.base64EncodedData(options: .endLineWithLineFeed)
        return String.init(data: newData, encoding: .utf8)
    }
    
    private static func base64Decode(_ string: String) -> Data? {
        return Data.init(base64Encoded: string, options: Data.Base64DecodingOptions.ignoreUnknownCharacters)
    }
    
    
    private static func stripPublicKeyHeader(_ d_key: Data?) -> Data? {
        guard let dKey = d_key else {
            return nil
        }
        let len = dKey.count
        if len == 0 {
            debugLog("加密失败： if len == 0 {")
            return nil
        }
        
        let cKey = dataToBytes(dKey)
        var index = 0
        
        if cKey[index] != 0x30 {
            debugLog("加密失败： if cKey[index] != 0x30 {")
            return nil
        }
        index += 1
        
        if cKey[index] > 0x80 {
            index += Int(cKey[index]) - 0x80 + 1
        } else {
            index += 1
        }
        
        //        if #available(iOS 13.0, *) {
        //            let swqiod:[CUnsignedChar] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
        //                                          0x01, 0x05, 0x00]
        //            // iOS 12系统 release下 这里会导致加密失败，debug下不会失败，很奇怪，所以13及以上系统才走这里
        //            if (memcmp(&cKey[index], swqiod, 15) == 1) {
        //                debugLog("加密失败： if (memcmp(&cKey[index], swqiod, 15) == 1) {")
        //                return nil
        //            }
        //        }
        //        index += 15
        
        let seqiod = [UInt8](arrayLiteral: 0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00)
        
        for i in index..<index+seqiod.count {
            if ( cKey[i] != seqiod[i-index] ) {
                debugLog("加密失败： if ( cKey[i] != seqiod[i-index] ) {")
                return nil
            }
        }
        index += seqiod.count
        
        if cKey[index] != 0x03 {
            debugLog("加密失败： if cKey[index] != 0x03 {2")
            return nil
        }
        index += 1
        
        if cKey[index] > 0x80 {
            index += Int(cKey[index]) - 0x80 + 1
        } else {
            index += 1
        }
        
        if cKey[index] != Unicode.Scalar.init("\0").value {
            debugLog("加密失败： if cKey[index] != Unicode.Scalar.init ")
            return nil
        }
        
        index += 1
        
        return Data.init(cKey).advanced(by: index)
    }
    
    private static func stripPrivateKeyHeader(_ d_key: Data?) -> Data? {
        guard let dKey = d_key else {
            return nil
        }
        let len = dKey.count
        if len == 0 {
            return nil
        }
        
        var cKey = dataToBytes(dKey)
        var index = 22
        
        if cKey[index] != 0x04 {
            return nil
        }
        index += 1
        
        var cLen = Int(cKey[index])
        index += 1
        let det = cLen & 0x80
        if det == 0 {
            cLen = cLen & 0x7f
        } else {
            var byteCount = Int(cLen & 0x7f)
            if Int(byteCount) + index > len {
                return nil
            }
            var accum = 0
            var ptr = withUnsafePointer(to: &cKey[index]) { $0 }
            index += Int(byteCount)
            while byteCount > 0 {
                accum = (accum << 8) + Int(ptr.pointee)
                ptr = ptr.advanced(by: 1)
                byteCount -= 1
            }
            cLen = accum
        }
        guard let range = Range.init(_NSRange.init(location: index, length: Int(cLen))) else {
            return nil
        }
        return dKey.subdata(in: range)
    }
    
    /// 公钥字符串转SecKey
    /// - Parameter key: 公钥字符串
    /// - Returns: SecKey
    private static func addPublicKey(_ key: String) -> SecKey? {
        var newKey = key
        debugLog("addPublicKey: newKey: \(newKey)")
        let spos = newKey.range(of: "-----BEGIN KEY-----")
        let epos = newKey.range(of: "-----END KEY-----")
        if spos != nil && epos != nil {
            newKey = String(newKey[spos!.upperBound..<epos!.lowerBound])
        }
        newKey = newKey.replacingOccurrences(of: "\r", with: "")
        newKey = newKey.replacingOccurrences(of: "\n", with: "")
        newKey = newKey.replacingOccurrences(of: "\t", with: "")
        newKey = newKey.replacingOccurrences(of: " ", with: "")
        
        guard let data = base64Decode(newKey) else {
            debugLog("加密失败, 结果为空: base64Decode")
            return nil
        }
        
        guard let data = stripPublicKeyHeader(data) else {
            debugLog("加密失败, 结果为空: stripPublicKeyHeader")
            return nil
        }
        
        return addPublicKey(data)
    }
    
    static func addPublicKey(_ data: Data) -> SecKey? {
        let tag = "RSAUtil_PubKey"
        let d_tag = tag.data(using: .utf8)
        
        var publicKey = Dictionary<String, Any>.init()
        publicKey[kSecClass as String] = kSecClassKey
        publicKey[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        publicKey[kSecAttrApplicationTag as String] = d_tag
#if os(macOS)
        var error: Unmanaged<CFError>?
//        let accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.userPresence], &error)
        let accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleAfterFirstUnlock, [], &error)
        
        publicKey[kSecAttrAccessControl as String] = accessControl
#endif
        SecItemDelete(publicKey as CFDictionary)
        
        publicKey[kSecValueData as String] = data
        publicKey[kSecAttrKeyClass as String] = kSecAttrKeyClassPublic
        publicKey[kSecReturnPersistentRef as String] = true
        var status = SecItemAdd(publicKey as CFDictionary, nil)
        
        if status != noErr && status != errSecDuplicateItem {
            return nil
        }
        
        publicKey.removeValue(forKey: kSecValueData as String)
        publicKey.removeValue(forKey: kSecReturnPersistentRef as String)
        publicKey[kSecReturnRef as String] = NSNumber(value: true)
        publicKey[kSecAttrKeyType as String] = kSecAttrKeyTypeRSA
        
        var keyRef: CFTypeRef?
        status = SecItemCopyMatching(publicKey as CFDictionary, &keyRef)
        if status != noErr {
            return nil
        }
        return (keyRef as! SecKey)
    }
    
    /// 私钥字符串转SecKey
    /// - Parameter key: 私钥字符串
    /// - Returns: SecKey
    private static func addPrivateKey(_ key: String) -> SecKey? {
        var newKey = key
        var spos: Range<String.Index>?
        var epos: Range<String.Index>?
        spos =  newKey.range(of: "-----BEGIN RSA PRIVATE KEY-----")
        if spos != nil {
            epos = newKey.range(of: "-----END RSA PRIVATE KEY-----")
        } else {
            spos = newKey.range(of: "-----BEGIN PRIVATE KEY-----")
            epos = newKey.range(of: "-----END PRIVATE KEY-----")
        }
        if spos != nil && epos != nil {
            newKey = String(newKey[spos!.upperBound..<epos!.lowerBound])
        }
        newKey = newKey.replacingOccurrences(of: "\r", with: "")
        newKey = newKey.replacingOccurrences(of: "\n", with: "")
        newKey = newKey.replacingOccurrences(of: "\t", with: "")
        newKey = newKey.replacingOccurrences(of: " ", with: "")
        
        guard let data = base64Decode(newKey),
              let data = stripPrivateKeyHeader(data) else {
            return nil
        }
        return addPrivateKey(data)
    }
    
    private static func addPrivateKey(_ data: Data) -> SecKey? {
        let tag = "RSAUtil_PrivKey"
        let d_tag = tag.data(using: .utf8)
        
        var privateKey = Dictionary<CFString, Any>.init()
        privateKey[kSecClass] = kSecClassKey
        privateKey[kSecAttrKeyType] = kSecAttrKeyTypeRSA
        privateKey[kSecAttrApplicationTag] = d_tag
#if os(macOS)
        var error: Unmanaged<CFError>?
//        let accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, [.userPresence], &error)
        let accessControl = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleAfterFirstUnlock, [], &error)
        
        privateKey[kSecAttrAccessControl] = accessControl
#endif
        SecItemDelete(privateKey as CFDictionary)
        
        privateKey[kSecValueData] = data
        privateKey[kSecAttrKeyClass] = kSecAttrKeyClassPrivate
        privateKey[kSecReturnPersistentRef] = true
        
        var persistKey: CFTypeRef?
        var status = SecItemAdd(privateKey as CFDictionary, &persistKey)
        
        if status != noErr && status != errSecDuplicateItem {
            return nil
        }
        
        privateKey.removeValue(forKey: kSecValueData)
        privateKey.removeValue(forKey: kSecReturnPersistentRef)
        privateKey[kSecReturnRef] = true
        privateKey[kSecAttrKeyType] = kSecAttrKeyTypeRSA
        
        var keyRef: CFTypeRef?
        status = SecItemCopyMatching(privateKey as CFDictionary, &keyRef)
        if status != noErr {
            return nil
        }
        return (keyRef as! SecKey)
    }
    
    private static func encrypt(_ data: Data, with secKey: SecKey, and isSign: Bool) -> Data? {
        var srcbuf = dataToBytes(data)
        let srclen = data.count
        // 在iOS 12或者更低版本上运行的代码
        let block_size = SecKeyGetBlockSize(secKey) * MemoryLayout<UInt8>.size
        var outbuf = [UInt8](repeating: 0, count: block_size)
        let src_block_size = block_size - 11
        
        var ret: Data? = Data()
        var index = 0
        while index < srclen {
            var data_len = srclen - index
            if data_len > src_block_size {
                data_len = src_block_size
            }
            
#if os(macOS)
            var result: CFData?
            var error: Unmanaged<CFError>?
            let sub = Data(srcbuf[index..<index+data_len])
            if isSign {
                // 用于签名， 使用私钥创建签名，然后使用公钥验证签名
                result = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, sub as CFData, &error)
            } else {
                result = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, sub as CFData, &error)
            }
            if let result = result as? Data {
                ret?.append(contentsOf: result)
            }
#else
            if #available(iOS 15, *) {
                var result: CFData?
                var error: Unmanaged<CFError>?
                let sub = Data(srcbuf[index..<index+data_len])
                if isSign {
                    // 用于签名， 使用私钥创建签名，然后使用公钥验证签名
                    result = SecKeyCreateSignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, sub as CFData, &error)
                } else {
                    result = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, sub as CFData, &error)
                }
                if let result = result as? Data {
                    ret?.append(contentsOf: result)
                }
            } else {
                var outlen = block_size
                var status = noErr
                let ptr = withUnsafePointer(to: &srcbuf[index]) { $0 }
                if isSign {
                    
                    // 用于签名， 使用私钥创建签名，然后使用公钥验证签名
                    status = SecKeyRawSign(secKey, SecPadding.PKCS1, ptr, data_len, &outbuf, &outlen)
                } else {
                    // 用于加密，使用公钥对数据进行加密，然后使用私钥对数据进行解密
                    status = SecKeyEncrypt(secKey, SecPadding.PKCS1, ptr, data_len, &outbuf, &outlen)
                }
                if status != 0 {
                    ret = nil
                    break
                } else {
                    ret?.append(contentsOf: outbuf[0..<outlen])
                }
            }
#endif
            
            index += src_block_size
        }
        
        return ret
        
    }
    
    private static func decrypt(_ data: Data, with secKey: SecKey) -> Data? {
        var srcbuf = dataToBytes(data)
        let srclen = data.count
        
        let block_size = SecKeyGetBlockSize(secKey) * MemoryLayout<UInt8>.size
        var outbuf = [UInt8](repeating: 0, count: block_size)
        let src_block_size = block_size
        
        var ret: Data? = Data()
        var index = 0
        while index < srclen {
            var data_len = srclen - index
            if data_len > src_block_size {
                data_len = src_block_size
            }
#if os(macOS)
            var error: Unmanaged<CFError>?
            let sub = Data(srcbuf[index..<index+data_len])
            let result = SecKeyCreateDecryptedData(secKey, .rsaEncryptionPKCS1, data as CFData, &error)
            if let result = result as? Data {
                ret?.append(contentsOf: result)
            }
#else
            if #available(iOS 15, *) {
                var error: Unmanaged<CFError>?
                let sub = Data(srcbuf[index..<index+data_len])
                let result = SecKeyCreateDecryptedData(secKey, .rsaEncryptionPKCS1, data as CFData, &error)
                if let result = result as? Data {
                    ret?.append(contentsOf: result)
                }
            } else {
                var outlen = block_size
                var status = noErr
                
                let ptr = withUnsafePointer(to: &srcbuf[index]) { $0 }
                status = SecKeyDecrypt(secKey, SecPadding.PKCS1, ptr, data_len, &outbuf, &outlen)
                
                if status != 0 {
                    ret = nil
                    break
                } else {
                    var idxFirstZero = -1
                    var idxNextZero = Int(outlen)
                    for i in 0..<outlen {
                        if outbuf[i] == 0 {
                            if idxFirstZero < 0 {
                                idxFirstZero = i
                            } else {
                                idxNextZero = i
                                break
                            }
                        }
                    }
                    ret?.append(contentsOf: outbuf[idxFirstZero+1..<idxNextZero])
                }
                
            }
#endif
            index += src_block_size
        }
        
        return ret
    }
    
    /// 从.der证书获取公钥
    /// - Parameter der: .der证书路径
    /// - Returns: 公钥
    private static func loadPublicKey(_ path: String) -> SecKey? {
        let data: Data;
        do {
            data = try Data.init(contentsOf: URL.init(fileURLWithPath: path))
        } catch {
            return nil
        }
        
        guard let cert = SecCertificateCreateWithData(nil, data as CFData) else {
            return nil
        }
        
        let key: SecKey?
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        if SecTrustCreateWithCertificates(cert, policy, &trust) == noErr {
//            var result = SecTrustResultType.invalid
            if let trust {
                if  SecTrustEvaluateWithError(trust, nil) {
                    if #available(iOS 14, *) {
                        key = SecTrustCopyKey(trust)
                    } else {
                        key = SecTrustCopyPublicKey(trust)
                    }
                    return key
                }
            }
        }
        return nil
    }
    
    /// 从.p12证书获取私钥
    /// - Parameters:
    ///   - path: .p12证书路径
    ///   - password: ,p12证书密码
    /// - Returns: 私钥
    private static func loadPrivateKey(_ path: String, with password: String = "") -> SecKey? {
        let data: Data
        do {
            data = try Data.init(contentsOf: URL.init(fileURLWithPath: path))
        } catch {
            return nil
        }
        
        var key: SecKey?
        let options = NSMutableDictionary.init()
        options[kSecImportExportPassphrase as String] = password
        var items: CFArray?
        var securityError = SecPKCS12Import(data as CFData, options, &items)
        if securityError == noErr && CFArrayGetCount(items) > 0 {
            let identityDict = CFArrayGetValueAtIndex(items, 0)
            let appKey = Unmanaged.passUnretained(kSecImportItemIdentity).toOpaque()
            let identityApp = CFDictionaryGetValue((identityDict as! CFDictionary), appKey)
            securityError = SecIdentityCopyPrivateKey(identityApp as! SecIdentity, &key)
            if securityError == noErr {
                return key
            }
        }
        return nil
    }
    
    /// Data转Byte(UInt8)数组
    /// - Parameter data: Data
    /// - Returns: Byte(UInt8)数组
    private static func dataToBytes(_ data: Data) -> [UInt8] {
//        let string = dataToHex(data)
//        var start = string.startIndex
//        return stride(from: 0, to: string.count, by: 2).compactMap { _ in
//            let end = string.index(after: start)
//            defer {start = string.index(after: end)}
//            return UInt8(string[start...end], radix: 16)
//        }
        // Data可直接转为[UInt8]，无需绕 16 进制
        return [UInt8](data)
    }
    
    /// Data转16进制字符串
    /// - Parameter data: Data
    /// - Returns: 16进制字符串
    private static func dataToHex(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var hex = ""
        for index in 0..<data.count {
            let newHex = String(format: "%x", bytes[index]&0xff)
            if newHex.count == 1 {
                hex = String(format: "%@0%@", hex, newHex)
            } else {
                hex += newHex
            }
        }
        return hex
    }
}
/*
 需加密的String: 15566688885 publicKey: MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCrDA3gFyJUBwEsQpKFDdoUdDIt
 i9M+cuhWONJlpRanMR7FsDskyJi1abwbynVSEWsmkT9thZqJuUgpO2eh2EijBNh7
 8sNMlZxjPGxmacNg3HlPJzdZWHDhDpu4MZfnSnfZqSQPrlj7SW+FnHVCSYX71Dx5
 eem6pdTisZB0AwwTpQIDAQAB
 
 
 加密后的字符串为：Optional("EC1SDYu6wBjj2zs9/uVtEvTLXhy1vfg26OtbkssO31WCn7wVwZ5OJCtuQJ8CF9/6\r\nzsw7TWkkzznhBUe4wP97VAg4T4DdD/qDpBdrf/QDUDCy3cVEBgHd+qtpOFAlS4dM\r\n9qm7CWJZmXhZ990HmznQrk/K4zKp7k67KvbSI0EPEaM="
 
 加密失败： if (memcmp(&cKey[index], swqiod, 15) == 1) {
 */
