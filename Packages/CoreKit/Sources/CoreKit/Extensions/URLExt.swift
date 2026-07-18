//
//  URLExt.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/13.
//

import Foundation
import CryptoKit

extension URL {
    // 获取文件hash
    func computeMD5() throws -> String {
        let data = try Data(contentsOf: self, options: .mappedIfSafe)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
