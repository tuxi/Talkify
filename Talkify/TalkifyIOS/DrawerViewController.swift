//
//  DrawerViewController.swift
//  Talkify
//
//  Created by xiaoyuan on 2026/7/19.
//

#if os(iOS)
import UIKit
import SwiftUI
import AgentKit

class DrawerViewController: UIViewController {
    
    var store: WorkspaceStore
    var searchText: String = ""
    
    var onSelectedConversation: (() -> Void)?
    var onSettingsTap: (() -> Void)?
    
    init(store: WorkspaceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let listView = ConversationListView(
            viewModel: store.listViewModel,
            selected: .init(get: {
                self.store.selectedConversation
            }, set: {
                self.store.selectedConversation = $0
                self.onSelectedConversation?()
            }),
            searchText: searchText
        )
        .background(.ultraThinMaterial)
        .environment(store)
        let rootController = UIHostingController(rootView: AnyView(listView))

        addChild(rootController)
        rootController.didMove(toParent: self)

        self.view.addSubview(rootController.view)
        rootController.view.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        rootController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        rootController.view.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        rootController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        
        let bottomBar = UIHostingController(
            rootView:
                BottomBar(onNewChatAction: {  [weak self] in
                    self?.store.beginDraft()
                    self?.onSelectedConversation?()
                }, onSettingsAction: { [weak self] in
                    self?.onSettingsTap?()
                })
        )
        bottomBar.view.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.view.backgroundColor = .clear
        addChild(bottomBar)
        view.addSubview(bottomBar.view)
        bottomBar.didMove(toParent: self)
        NSLayoutConstraint.activate([
            bottomBar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            bottomBar.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            bottomBar.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            bottomBar.view.heightAnchor.constraint(equalToConstant: 50)
        ])
        
    }
    
}

private struct BottomBar: View {
    
    let onNewChatAction: () -> Void
    let onSettingsAction: () -> Void
    
    
    var body: some View {
        HStack {
            Button {
                onNewChatAction()
            } label: {
                HStack {
                    Image(systemName: "square.and.pencil")
                    Text("聊天")
                }
                .foregroundColor(.white) // 避免文字与黑色背景冲突
                .padding(.horizontal, 16) // 增加聊天按钮内边距
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            }
            
            Spacer(minLength: 30)
            
            Button {
                onSettingsAction()
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.primary) // 设置齿轮颜色
                    .frame(width: 40, height: 40) // 固定等宽高以确保是正圆
                    .background(Color(.systemGray5)) // 灰色背景
                    .clipShape(Circle()) // 裁剪为正圆
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 15) // 为底部栏增加上下间距
//        .background(Color(.systemBackground)) // 底部栏背景色
        .clipShape(RoundedRectangle(cornerRadius: 20)) // 整个底部栏的圆角
    }
}


#endif
