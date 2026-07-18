//
//  PreviewAssetCacheState.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import Foundation

public enum PreviewAssetCacheState: Sendable, Equatable {
    case none
    case downloading(progress: Double?)
    case cached(localFileURL: URL)
    case failed(description: String)
}
