//
//  DateExt.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/16.
//


import Foundation

public extension Date {
   static func forma(timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
}

