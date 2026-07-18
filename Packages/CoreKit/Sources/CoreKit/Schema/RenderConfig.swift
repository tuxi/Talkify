
//
//  RenderConfig.swift
//  FeatureAdminUI
//
//  Created by xiaoyuan on 2026/4/4.
//

import Foundation
import CoreKit

public enum AdminRenderLayout: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case standard
    case compact
    case immersive

    public var id: String { rawValue }
}

public enum AdminRenderSectionType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case assetLibrary = "asset_library"

    public var id: String { rawValue }
}

public enum AdminRenderSelectionMode: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case single
    case multiple

    public var id: String { rawValue }
}

public enum AdminRenderAssetLayout: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case grid
    case list

    public var id: String { rawValue }
}

public enum AdminRenderAssetType: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case videoTemplate = "video_template"
    case imageTemplate = "image_template"
    case audioTemplate = "audio_template"
    case sellingPointTagTemplate = "selling_point_tag"

    public var id: String { rawValue }
}

public struct AdminRenderSectionConfig: Codable, Sendable, Hashable, Identifiable {
    public var id = UUID()

    public var key: String
    public var type: AdminRenderSectionType
    public var title: String
    public var subtitle: String?
    public var visible: Bool
    public var required: Bool
    public var layout: AdminRenderAssetLayout
    public var selectionMode: AdminRenderSelectionMode
    public var assetType: AdminRenderAssetType

    public init(
        key: String,
        type: AdminRenderSectionType = .assetLibrary,
        title: String,
        subtitle: String? = nil,
        visible: Bool = true,
        required: Bool = false,
        layout: AdminRenderAssetLayout = .grid,
        selectionMode: AdminRenderSelectionMode = .single,
        assetType: AdminRenderAssetType = .videoTemplate
    ) {
        self.key = key
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.visible = visible
        self.required = required
        self.layout = layout
        self.selectionMode = selectionMode
        self.assetType = assetType
    }

    public static func empty(sortSuffix: Int = 1) -> Self {
        .init(
            key: "section_\(sortSuffix)",
            title: "新素材区块"
        )
    }

    public static func motionTemplate() -> Self {
        .init(
            key: "motion_template",
            title: "动作模板",
            subtitle: "选择一个参考动作",
            visible: true,
            required: false,
            layout: .grid,
            selectionMode: .single,
            assetType: .videoTemplate
        )
    }
}

public struct AdminRenderConfig: Codable, Sendable, Hashable {
    public var showPromptSection: Bool
    public var showModelSection: Bool
    public var showStyleSection: Bool
    public var showPresetSection: Bool
    public var showAdvancedSection: Bool
    public var showGeneratePromptButton: Bool
    public var uploadSectionTitle: String
    public var layout: String

    /// 这里才是“素材区块定义”的真源
    public var sections: [AdminRenderSectionConfig]
    
    enum CodingKeys: String, CodingKey {
        case showPromptSection = "show_prompt_section"
        case showModelSection = "show_model_section"
        case showStyleSection = "show_style_section"
        case showPresetSection = "show_preset_section"
        case showAdvancedSection = "show_advanced_section"
        case showGeneratePromptButton = "show_generate_prompt_button"
        case uploadSectionTitle = "upload_section_title"
        case layout
        case sections
    }

    public init(
        showPromptSection: Bool = true,
        showModelSection: Bool = true,
        showStyleSection: Bool = true,
        showPresetSection: Bool = true,
        showAdvancedSection: Bool = false,
        showGeneratePromptButton: Bool = true,
        uploadSectionTitle: String = "上传素材",
        layout: String = AdminRenderLayout.standard.rawValue,
        sections: [AdminRenderSectionConfig] = []
    ) {
        self.showPromptSection = showPromptSection
        self.showModelSection = showModelSection
        self.showStyleSection = showStyleSection
        self.showPresetSection = showPresetSection
        self.showAdvancedSection = showAdvancedSection
        self.showGeneratePromptButton = showGeneratePromptButton
        self.uploadSectionTitle = uploadSectionTitle
        self.layout = layout
        self.sections = sections
    }
}
