//
//  AppModalCoordinator.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/4/19.
//

import Foundation
import Observation
import CoreKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
@Observable
final class AppModalCoordinator {
    var presentedCover: AppGlobalCoverDestination?
    var browserURL: BrowserURL?

    struct BrowserURL: Identifiable {
        let url: URL
        public var id: String { url.absoluteString }
    }

    func presentSubscription() {
        presentedCover = .subscription
    }

    func presentAuth() {
        presentedCover = .auth
    }

    func presentCover(_ dest: AppGlobalCoverDestination) {
        presentedCover = dest
    }

    func dismissCover() {
        presentedCover = nil
    }

    func openURL(_ url: URL) {
        if let appURL = resolveAppURL(url) {
            openURL(appURL)
            return
        }

        if url.scheme == "mailto" || url.scheme == "tel" {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        } else {
            browserURL = BrowserURL(url: url)
        }
    }

    private func resolveAppURL(_ url: URL) -> URL? {
        guard url.scheme == "dreamai" else { return nil }

        switch url.host {
        case "user-agreement":
            return AgreementURLs.terms
        case "privacy-policy":
            return AgreementURLs.privacy
        case "ai-data-processing":
            return AgreementURLs.AIData
        default:
            return nil
        }
    }

    func dismissAll() {
        presentedCover = nil
        browserURL = nil
    }
}
