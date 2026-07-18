//
//  CurrencyFormatter.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/23.
//

import Foundation

public enum CurrencyFormatter {
   public static func cnyString(fromFen amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: NSNumber(value: Double(amount) / 100.0)) ?? "¥\(Double(amount) / 100.0)"
    }
}

public extension Double {
    var cleanDisplay: String {
        if truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(self))
        }
        return String(format: "%.2f", self)
    }
}

public extension DateFormatter {
    public static let subscriptionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()
}
