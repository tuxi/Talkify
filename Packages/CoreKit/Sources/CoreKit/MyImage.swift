//
//  MyImage.swift
//  Chater
//
//  Created by xiaoyuan on 2023/8/31.
//

import SwiftUI
import AVFoundation

#if canImport(AppKit)
import AppKit
public typealias MyImage = NSImage
#else
import UIKit
public typealias MyImage = UIImage
#endif


extension Image {
    public init(myImage: MyImage) {
#if canImport(AppKit)
        self.init(nsImage: myImage)
#else
        self.init(uiImage: myImage)        
#endif
    }
    
    
}

extension MyImage {
    
    /// 生成视频第一帧作为缩略图，并保存为 PNG 格式到本地临时目录
    public static func generateThumbnailPath(for url: URL) async -> (MyImage, URL?) {
        // 1. 调用已有的生成方法获取 MyImage
        let image = await generateThumbnail(for: url)
        
        // 2. 将 MyImage 转换为 PNG Data
        let imageData: Data?
#if os(macOS)
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData) {
            imageData = bitmapImage.representation(using: .png, properties: [:])
        } else {
            imageData = nil
        }
#else
        imageData = image.pngData()
#endif
        
        guard let data = imageData else {
            DLLog("❌ Failed to convert MyImage to PNG data")
            return (image, nil)
        }
        
        // 3. 存储到临时目录
        do {
            let fileName = "thumb_\(UUID().uuidString).png"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            return (image, tempURL)
        } catch {
            DLLog("❌ Error saving thumbnail to path: \(error)")
            return (image, nil)
        }
    }
    
    /// 生成视频第一帧作为缩略图 (适配 MyImage 与 新版 AVKit)
  public static func generateThumbnail(for url: URL) async -> MyImage {
        // 使用 AVURLAsset 替代过期的 AVAsset(url:)
        let asset = AVURLAsset(url: url)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        
        // 确保缩略图方向正确
        assetImgGenerate.appliesPreferredTrackTransform = true
        // 容许微小的误差，提高生成速度
        assetImgGenerate.requestedTimeToleranceBefore = .zero
        assetImgGenerate.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        
      do {
          let (cgImage, _) = try await assetImgGenerate.image(at: time)
          
#if os(macOS)
          return MyImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
#else
          return MyImage(cgImage: cgImage)
#endif
          
      } catch {
          DLLog("❌ Error generating thumbnail image: \(error)")
#if os(macOS)
          return NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil) ?? NSImage()
#else
          return UIImage(systemName: "video.fill") ?? UIImage()
#endif
      }
    }
    
#if os(macOS)
    public func pngData() -> Data? {
        if let tiffData = tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData) {
            if let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                return pngData
            }
        }
        return nil
    }
    
    public func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiffRepresentation = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmapImage.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: compressionQuality])
    }
    
    public func resized(to newSize: CGSize) -> MyImage? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(newSize.width), pixelsHigh: Int(newSize.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        
        bitmap.size = newSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        
        self.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height), from: .zero, operation: .copy, fraction: 1.0)
        
        NSGraphicsContext.restoreGraphicsState()
        
        let newImage = NSImage(size: newSize)
        newImage.addRepresentation(bitmap)
        
        return newImage
    }
#endif
    
    public func cropped(to rect: CGRect) -> MyImage? {
        #if os(macOS)
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }
        return MyImage(cgImage: croppedCGImage, size: rect.size)
        #else
        guard let cgImage = self.cgImage,
              let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }
        return MyImage(cgImage: croppedCGImage)
        #endif
    }
    
#if os(iOS)
   public func resized(to newSize: CGSize) -> MyImage? {
        if #available(iOS 10.0, *) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = self.scale
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                self.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
            self.draw(in: CGRect(origin: .zero, size: newSize))
            let newImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return newImage
        }
    }
   
#endif
    
    // 压缩图片到最大的某个值
   public func compressedData(under maxSize: Int) -> (compression: CGFloat, data: Data)? {
        var compression: CGFloat = 1.0
        let step: CGFloat = 0.05
        var imageData = self.jpegData(compressionQuality: compression)
        
        while let data = imageData, data.count > maxSize && compression > 0 {
            compression -= step
            imageData = self.jpegData(compressionQuality: compression)
        }
        if let imageData {
            return (compression, imageData)
        }
        return nil
    }
}
