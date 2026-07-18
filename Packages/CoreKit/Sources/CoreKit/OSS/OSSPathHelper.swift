//
//  OSSPathHelper.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/13.
//

import Foundation

public enum OSSServiceModule: String {
    case dreams = "dreams"       // 织梦项目
    case meatOS = "meatos"       // 零售自动化项目
    case userAssets = "assets"   // 通用用户资产
    
}

public enum OSSResourceType: String {
    case video = "videos"
    case image = "images"
    case audio = "audios"
    case temp  = "temp"          // 临时文件，用于配置自动删除
    
    /// 是否为临时文件
    var isTemp: Bool { self == .temp }
}

// 资源二级子目录，用来区分头像/背景/普通图
public enum OSSSubDir: String {
    case avatar = "avatar"
    case background = "background"
    case common = "common"
    case upload = "upload"
}

public struct OSSPathHelper {
    
    /// 单例日期格式化器（避免重复创建消耗性能）
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8) // 东八区统一时间
        return formatter
    }()
    
    // MARK: - 生成头像路径（最精简）
    public static func avatarPath(
        userId: String,
        ext: String = "png"
    ) -> String {
        let cleanUserId = userId.trimmingCharacters(in: .alphanumerics.inverted)
        let cleanExt = ext.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return "assets/images/avatar/\(cleanUserId).\(cleanExt)"
    }
    
    // MARK: - 生成用户普通文件（带日期 + userId + uuid）
    public static func userAssetPath(
        type: OSSResourceType = .image,
        subDir: OSSSubDir = .common,
        userId: String,
        fileExtension: String
    ) -> String {
        let date = dateFormatter.string(from: Date())
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let ext = fileExtension.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let filename = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        
        let components: [String] = [
            OSSServiceModule.userAssets.rawValue,
            type.rawValue,
            subDir.rawValue,
            date,
            userId,
            filename
        ]
        
        return components.joined(separator: "/")
    }
    
    // MARK: - 业务文件（dreams / meatos）
    public static func businessPath(
        module: OSSServiceModule,
        type: OSSResourceType,
        userId: String,
        fileExtension: String
    ) -> String {
        let date = dateFormatter.string(from: Date())
        let uuid = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let ext = fileExtension.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let filename = ext.isEmpty ? uuid : "\(uuid).\(ext)"
        
        let components: [String] = [
            module.rawValue,
            type.rawValue,
            date,
            userId,
            filename
        ]
        
        return components.joined(separator: "/")
    }
}


