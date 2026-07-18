//
//  AppSign.swift
//  FeatureAuth
//
//  Created by xiaoyuan on 2026/3/2.
//

import Foundation
import CoreKit

struct AppSign {
    
    private static var publicKey: String {
        """
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoqT05dP9QcbI9le23zIG
        QRv1NNyfJ3ZBDVGOnto3o/1pUlcrn9Q5NmmqAwbT5EKl5Cw2/Rlouy4SrIxkuaW/
        8296c6uXUwcvKdmzh11LKpX1ZhEh6Jj2Y4lovA/5W58xl36dwmBG100G5hHIF36x
        g8ievhvg9cjil+Vlo7bu7CkBy5ur7/59oRBgUMOONyxwiEGUm5GU91a8YyFOMC0z
        jGPDSQqQsrzKdrPtaXXVc24PEWxrKLP77KNjOTv/RYbqKBK5nC1YJRpo/6QYmLBC
        /VYl+8oRo543x+Ktl71RxIWN1FcXPsvBhMviney1B3hhsSU54PNT+6pJnhdtzRZC
        xwIDAQAB
        """
    }
    
    
    static func encrypt(plaintext: String) -> String? {
        let str = RSA.encryptString(plaintext, publicKey: publicKey)
        return str
    }
    
    static func encrypt<T: Encodable>(_ info: T) -> String? {
        let data = try! JSONEncoder().encode(info)
        guard let jsonStr = String(data: data, encoding: .utf8) else {
            return nil
        }
        let str = RSA.encryptString(jsonStr, publicKey: publicKey)
        return str
    }
    
    
}
