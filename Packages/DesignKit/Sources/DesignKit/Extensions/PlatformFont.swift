//
//  PlatformFont.swift
//  DesignKit
//
//  Created by xiaoyuan on 2026/4/21.
//

#if canImport(UIKit)
import UIKit
public typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
public typealias PlatformFont = NSFont
#endif

public extension String {
    func height(with font: PlatformFont, width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let rect = self.boundingRect(with: size,
                                     options: [.usesLineFragmentOrigin, .usesFontLeading],
                                     attributes: [.font: font],
                                     context: nil)
        return ceil(rect.height)
    }
}
