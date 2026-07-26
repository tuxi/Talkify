//
//  CurrencyFormatter.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/23.
//

import Foundation

public enum CurrencyFormatter {
    public static func currencyString(fromMinorUnits amount: Int, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.uppercased()
        formatter.locale = .current
        let value = Double(amount) / 100.0
        return formatter.string(from: NSNumber(value: value)) ?? "\(currencyCode.uppercased()) \(value.cleanDisplay)"
    }

    public static func cnyString(fromFen amount: Int) -> String {
        currencyString(fromMinorUnits: amount, currencyCode: "CNY")
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
    static let subscriptionDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
