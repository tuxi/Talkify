//
//  DataExt.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/5.
//

import Foundation
import CryptoKit

public extension Data {
    func sha256Hash() -> String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
