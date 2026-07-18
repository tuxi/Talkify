//
//  OutputConfig.swift
//  FeatureAdminUI
//
//  Created by xiaoyuan on 2026/4/4.
//

public struct AdminOutputConfig: Codable, Sendable, Hashable {
    public var outputType: String
    public var autoSaveToAlbum: Bool
    public var showShareButton: Bool
    public var showRetryButton: Bool
    public var showTaskInfo: Bool

    public init(
        outputType: String = "video",
        autoSaveToAlbum: Bool = false,
        showShareButton: Bool = true,
        showRetryButton: Bool = true,
        showTaskInfo: Bool = true
    ) {
        self.outputType = outputType
        self.autoSaveToAlbum = autoSaveToAlbum
        self.showShareButton = showShareButton
        self.showRetryButton = showRetryButton
        self.showTaskInfo = showTaskInfo
    }
}
