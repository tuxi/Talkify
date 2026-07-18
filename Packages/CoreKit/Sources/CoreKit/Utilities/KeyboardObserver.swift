//
//  File.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/3/21.
//

import SwiftUI
import Combine

// 键盘监听器
@MainActor
public final class KeyboardObserver: ObservableObject {
    @Published public var height: CGFloat = 0
    @Published public var animationDuration: Double = 0.25
    
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        #if os(iOS)
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        
        willChange
            .merge(with: willHide)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let userInfo = notification.userInfo else { return }
                
                let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                self.animationDuration = duration
                let window = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: \.isKeyWindow)
                guard
                    let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                    let window
                else {
                    self.height = 0
                    return
                }
                
                let keyboardFrameInWindow = window.convert(endFrame, from: nil)
                let intersection = window.bounds.intersection(keyboardFrameInWindow)
                
                let bottomSafeInset = window.safeAreaInsets.bottom
                let visibleKeyboardHeight = max(0, intersection.height - bottomSafeInset)
                
                self.height = visibleKeyboardHeight
            }
            .store(in: &cancellables)
        #endif
    }
}
