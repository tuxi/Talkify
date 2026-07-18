//
//  PhotoStore.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/20.
//

import Photos
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public class PhotoStore {
    public static func saveImage(_ image: MyImage) async throws {
        // 请求权限
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "PhotoStore", code: 0, userInfo: [NSLocalizedDescriptionKey: "没有相册访问权限"])
        }
        
        // 执行保存
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
