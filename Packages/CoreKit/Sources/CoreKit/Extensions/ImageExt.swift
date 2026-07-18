//
//  File.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/21.
//

#if os(iOS)
import UIKit

extension UIImage {
    
    public func resizedIfNeeded(maxLongEdge: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return self }
        
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}


extension UIImage {
    
    public func normalizedImage() -> UIImage {
        if imageOrientation == .up { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalized ?? self
    }
    
    /// 先按目标比例居中裁切，再缩放到目标尺寸
    public func centerCropAndResize(to targetSize: CGSize) -> UIImage {
        let sourceSize = size
        let sourceRatio = sourceSize.width / sourceSize.height
        let targetRatio = targetSize.width / targetSize.height

        var cropRect = CGRect(origin: .zero, size: sourceSize)

        if sourceRatio > targetRatio {
            // 原图更宽，裁左右
            let cropWidth = sourceSize.height * targetRatio
            let x = (sourceSize.width - cropWidth) / 2.0
            cropRect = CGRect(x: x, y: 0, width: cropWidth, height: sourceSize.height)
        } else if sourceRatio < targetRatio {
            // 原图更高，裁上下
            let cropHeight = sourceSize.width / targetRatio
            let y = (sourceSize.height - cropHeight) / 2.0
            cropRect = CGRect(x: 0, y: y, width: sourceSize.width, height: cropHeight)
        }

        guard let cgImage = self.cgImage?.cropping(to: cropRect.scaled(by: scale)) else {
            return resized(to: targetSize)
        }

        let cropped = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        return cropped.resized(to: targetSize)
    }
    
    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

#else
import AppKit

extension NSImage {
    public func resizedIfNeeded(maxLongEdge: CGFloat) -> NSImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return self }
        
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: CGRect(origin: .zero, size: newSize),
             from: CGRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
//    public func jpegData(compressionQuality: CGFloat) -> Data? {
//        guard let tiffData = tiffRepresentation,
//              let rep = NSBitmapImageRep(data: tiffData) else {
//            return nil
//        }
//        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
//    }
    
    public func normalizedImage() -> MyImage {
        return self
    }
}
#endif

private extension CGRect {
    func scaled(by scale: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * scale,
            y: origin.y * scale,
            width: size.width * scale,
            height: size.height * scale
        )
    }
}
