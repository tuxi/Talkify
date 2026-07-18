//
//  RouterPath.swift
//  Dreamlog
//
//  Created by xiaoyuan on 2026/3/20.
//

import Foundation
import Observation

@MainActor
@Observable
public final class RouterPath<Route: Hashable, Sheet: Identifiable & Equatable, Cover: Identifiable & Equatable> {
    public var path: [Route] = []
    public var presentedSheet: Sheet?
    public var presentedCover: Cover?
    
    public var onDismiss: (() -> Void)?
    
    public init() {
//        print("🚨 RouterPath.init: ", self)
    }

    public func navigate(to destination: Route) {
//        print("🚨 RouterPath.navigate: ", destination)
        path.append(destination)
    }

    public func pop() {
//        print("🚨 RouterPath.pop")
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
//        print("🚨 RouterPath.popToRoot")
        path.removeAll()
        presentedSheet = nil     // 关闭所有 Sheet
        presentedCover = nil     // 关闭所有 Cover
    }
    

    public func presentSheet(_ destination: Sheet) {
//        print("🚨 RouterPath.presentSheet:", destination)
        presentedSheet = destination
    }

    public func dismissSheet() {
//        print("🚨 RouterPath.dismissSheet")
        presentedSheet = nil
        onDismiss?()
    }

    public func presentCover(_ destination: Cover) {
//        print("🚨 RouterPath.presentCover: ", destination)
        presentedCover = destination
    }

    public func dismissCover() {
//        print("🚨 RouterPath.dismissCover")
        presentedCover = nil
        onDismiss?()
    }

    public func dismissAllModals() {
//        print("🚨 RouterPath.dismissAllModals")
        presentedSheet = nil
        presentedCover = nil
        onDismiss?()
    }
}
