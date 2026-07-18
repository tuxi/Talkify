//
//  PreviewPlaybackLogger.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/11.
//

import Foundation

public enum PreviewPlaybackLogger {
    public static let isEnabled: Bool = false

    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        DLLog("[PreviewPlayback] \(message())")
    }

    public static func logEvent(_ name: String, fields: [String: String] = [:]) {
        guard isEnabled else { return }

        let payload = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        if payload.isEmpty {
            DLLog("[PreviewPlayback][Event] \(name)")
        } else {
            DLLog("[PreviewPlayback][Event] \(name) \(payload)")
        }
    }
}
