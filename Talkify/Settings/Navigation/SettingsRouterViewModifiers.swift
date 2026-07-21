//
//  SettingsRouterViewModifiers.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/21.
//

import SwiftUI

@MainActor
extension View {
   
    func withSettingsNavigationDestinations(
            router: SettingsRouter,
    ) -> some View {
        navigationDestination(for: SettingsNavigationDestination.self) { destination in
            
        }
    }
    
   func withSettingsSheetDestinations(
        sheetDestinations: Binding<SettingsSheetDestination?>
    ) -> some View {
        return sheet(item: sheetDestinations) { destination in
            switch destination {
            case .demo:
                Color.red
            }
        }
    }
    
   func withSettingsCoverDestinations(
        coverDestinations: Binding<SettingsCoverDestination?>
    ) -> some View {
        // 使用一个统一的辅助方法来渲染内容
        let sheetContent = { (destination: SettingsCoverDestination) -> AnyView in
            let view: AnyView
            switch destination {
            case .demo:
                view = AnyView(Color.blue)
            }
            return view
        }
        
#if os(macOS)
        return sheet(item: coverDestinations) {
            sheetContent($0)
                .frame(minWidth: 600, minHeight: 450) // macOS 需要给个默认大小
        }
#else
        return fullScreenCover(item: coverDestinations, content: sheetContent)
#endif
    }
}
