//
//  AdminBuiltinFieldTemplate.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/9.
//

import Foundation
import CoreKit

/*
 带货视频单商品模式 input schema
 {
   "fields": [
     {
       "key": "product_images",
       "title": "商品图片",
       "type": "image",
       "required": true,
       "visible": true,
       "sort": 10
     },
     {
       "key": "product_name",
       "title": "商品名称",
       "type": "text",
       "required": true,
       "visible": true,
       "sort": 20
     },
     {
       "key": "product_description",
       "title": "商品描述",
       "type": "prompt",
       "required": true,
       "visible": true,
       "sort": 30
     },
     {
       "key": "selling_points",
       "title": "核心卖点",
       "type": "text",
       "required": false,
       "visible": true,
       "sort": 40
     },
     {
       "key": "target_platform",
       "title": "目标平台",
       "type": "select",
       "required": false,
       "visible": true,
       "sort": 50,
       "rules": {
         "allowedValues": ["douyin", "xiaohongshu", "wechat_channels", "tiktok"]
       }
     },
     {
       "key": "user_prompt",
       "title": "补充创意描述",
       "type": "prompt",
       "required": false,
       "visible": true,
       "sort": 60
     },
 {
   "key": "human_presence_mode",
   "title": "人物出镜",
   "type": "select",
   "required": false,
   "visible": true,
   "rules": {
     "allowedValues": [
       "no_human",
       "hands_only",
       "with_person_no_face",
       "with_face"
     ]
   }
 },
     {
       "key": "duration",
       "title": "时长",
       "type": "duration",
       "required": true,
       "visible": true,
       "sort": 70,
       "rules": {
         "allowedValues": ["10", "15", "30"]
       }
     },
     {
       "key": "resolution",
       "title": "分辨率",
       "type": "resolution",
       "required": true,
       "visible": true,
       "sort": 80,
       "rules": {
         "allowedValues": ["720p", "1080p"]
       }
     },
     {
       "key": "aspect_ratio",
       "title": "画面比例",
       "type": "aspectRatio",
       "required": true,
       "visible": true,
       "sort": 90,
       "rules": {
         "allowedValues": ["9:16", "1:1", "16:9"]
       }
     },
     {
       "key": "model",
       "title": "模型",
       "type": "model",
       "required": false,
       "visible": true,
       "sort": 100
     },
     {
       "key": "style",
       "title": "风格",
       "type": "style",
       "required": false,
       "visible": true,
       "sort": 110
     }
   ]
 }
 套模板模式建议 sections
 {
   "key": "template_library",
   "title": "模板库",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": true,
   "required": true,
   "layout": "horizontal_cards",
   "asset_type": "commerce_template",
   "has_items": true,
   "query_path": "/tool-assets/commerce/template-library"
 }
 
 {
   "id": "STYLE_PRESETS_SECTION_ID",
   "key": "style_presets",
   "type": "asset_library",
   "title": "风格模板",
   "layout": "horizontal_cards",
   "visible": true,
   "required": false,
   "assetType": "style_preset",
   "selectionMode": "single"
 }
 
 文案模版
 {
   "key": "copywriting_presets",
   "title": "文案方向",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": false,
   "required": false,
   "layout": "chips",
   "asset_type": "copy_preset",
   "has_items": true,
   "query_path": "/tool-assets/commerce/copy-presets"
 }
 卖点建议
 {
   "key": "selling_point_suggestions",
   "title": "推荐卖点",
   "type": "asset_library",
   "selection_mode": "multiple",
   "visible": true,
   "required": false,
   "layout": "chips",
   "asset_type": "selling_point_tag",
   "has_items": true,
   "query_path": "/tool-assets/commerce/selling-points"
 }
 

 
 风格预设
 {
   "key": "style_presets",
   "title": "风格模板",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": true,
   "required": false,
   "layout": "horizontal_cards",
   "asset_type": "style_preset",
   "has_items": true,
   "query_path": "/tool-assets/commerce/style-presets"
 }
 
 平台预设
 {
   "key": "platform_presets",
   "title": "平台玩法",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": false,
   "required": false,
   "layout": "chips",
   "asset_type": "platform_preset",
   "has_items": true,
   "query_path": "/tool-assets/commerce/platform-presets"
 }
 推荐模板
 
 {
   "key": "recommended_templates",
   "title": "推荐模板",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": true,
   "required": false,
   "layout": "horizontal_cards",
   "asset_type": "commerce_template",
   "has_items": true,
   "query_path": "/tool-assets/commerce/templates"
 }
 
 热门案例
 {
   "key": "hot_cases",
   "title": "热门案例",
   "type": "asset_library",
   "selection_mode": "single",
   "visible": true,
   "required": false,
   "layout": "horizontal_cards",
   "asset_type": "video_case",
   "has_items": true,
   "query_path": "/tool-assets/commerce/hot-cases"
 }
 
 asset extra
 {
   "default_values": {
     "style": "premium",
     "duration": 15,
     "aspect_ratio": "9:16",
     "resolution": "1080p"
   },
   "tone": "高级",
   "pace": "中快",
   "subtitle_style": "clean"
 }
 
 asset extra 建议字段
 
 {
   "mode_key": "template_based_product_video",
   "initial_input": {
     "style": "premium_product",
     "duration": 15,
     "aspect_ratio": "9:16"
   },
   "industry": "beauty",
   "preview_title": "高级护肤品质感短片",
   "preview_subtitle": "适合抖音种草",
   "cta_text": "一键同款"
 }
 */

public enum ToolBuiltinFieldKey {
    public static let images = "images"
    public static let userPrompt = "user_prompt"
    public static let model = "model"
    public static let style = "style"
    public static let duration = "duration"
    public static let shotDuration = "shot_duration"
    public static let resolution = "resolution"
    public static let aspectRatio = "aspect_ratio"
    public static let material = "material"
    public static let fps = "fps"
    public static let watermark = "watermark"
    public static let negativePrompt = "negative_prompt"
    public static let motionTemplate = "motion_template"
//    public static let size = "size" // 图片生成专用
//    public static let quality = "quality" // 图片生成专用
}

// 内建字段模板
public enum AdminBuiltinFieldTemplate {
   public static func makeField(for type: ToolInputFieldType) -> ToolInputFieldSchema {
        switch type {
        case .image:
            return .init(
                key: ToolBuiltinFieldKey.images,
                title: "上传图片",
                type: .image,
                required: true,
                visible: true,
                sort: 10,
                rules: .init(minCount: 1, maxCount: 1)
            )

        case .prompt:
            return .init(
                key: ToolBuiltinFieldKey.userPrompt,
                title: "提示词",
                type: .prompt,
                required: true,
                visible: true,
                sort: 20,
                placeholder: "请输入内容"
            )

        case .model:
            return .init(
                key: ToolBuiltinFieldKey.model,
                title: "模型",
                type: .model,
                required: true,
                visible: true,
                sort: 30
            )

        case .style:
            return .init(
                key: ToolBuiltinFieldKey.style,
                title: "样式",
                type: .style,
                required: false,
                visible: true,
                sort: 40
            )

        case .duration:
            return .init(
                key: ToolBuiltinFieldKey.duration,
                title: "时长",
                type: .duration,
                required: true,
                visible: true,
                sort: 50,
                rules: .init(allowedValues: ["4", "6", "8"])
            )

        case .resolution:
            return .init(
                key: ToolBuiltinFieldKey.resolution,
                title: "分辨率",
                type: .resolution,
                required: true,
                visible: true,
                sort: 60,
                rules: .init(allowedValues: ["720p", "1080p"])
            )

        case .aspectRatio:
            return .init(
                key: ToolBuiltinFieldKey.aspectRatio,
                title: "画幅",
                type: .aspectRatio,
                required: true,
                visible: true,
                sort: 70,
                rules: .init(allowedValues: ["9:16", "16:9", "1:1"])
            )

        case .material:
            return .init(
                key: ToolBuiltinFieldKey.material,
                title: "素材",
                type: .material,
                required: false,
                visible: true,
                sort: 80
            )

        case .video:
            return .init(
                key: "video_url",
                title: "视频",
                type: .video,
                required: true,
                visible: true,
                sort: 10
            )

        case .text:
            return .init(
                key: "text_field",
                title: "文本字段",
                type: .text,
                required: false,
                visible: true,
                sort: 100
            )

        case .number:
            return .init(
                key: "number_field",
                title: "数字字段",
                type: .number,
                required: false,
                visible: true,
                sort: 100,
                rules: .init(minValue: 0, maxValue: 100)
            )

        case .toggle:
            return .init(
                key: "toggle_field",
                title: "开关字段",
                type: .toggle,
                required: false,
                visible: true,
                sort: 100
            )

        case .select:
            return .init(
                key: "select_field",
                title: "选择字段",
                type: .select,
                required: false,
                visible: true,
                sort: 100,
                rules: .init(allowedValues: ["A", "B"])
            )
        case .mutilSelect:
            return .init(
                key: "mutil_select_field",
                title: "多选字段",
                type: .mutilSelect,
                required: false,
                sort: 120,
                rules: .init(allowedValues: ["A", "B", "C"])
            )
        }
    }

    public static func fallbackAllowedValues(for type: ToolInputFieldType) -> [String] {
        switch type {
        case .aspectRatio:
            return ["9:16", "16:9", "1:1"]
        case .resolution:
            return ["720p", "1080p"]
        case .duration:
            return ["4", "6", "8"]
        default:
            return []
        }
    }

    public static func isBuiltinReservedKey(_ key: String) -> Bool {
        [
            ToolBuiltinFieldKey.images,
            ToolBuiltinFieldKey.userPrompt,
            ToolBuiltinFieldKey.model,
            ToolBuiltinFieldKey.style,
            ToolBuiltinFieldKey.duration,
            ToolBuiltinFieldKey.resolution,
            ToolBuiltinFieldKey.aspectRatio,
            ToolBuiltinFieldKey.material,
            ToolBuiltinFieldKey.fps,
            ToolBuiltinFieldKey.watermark,
            ToolBuiltinFieldKey.negativePrompt,
            ToolBuiltinFieldKey.motionTemplate
        ].contains(key)
    }
}
