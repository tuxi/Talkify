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
    
    init(store: WorkspaceStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        view.backgroundColor = UIColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1)

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
        .environment(store)
        let rootController = UIHostingController(rootView: AnyView(listView))
//        rootController.view.backgroundColor = .clear

        self.addChild(rootController)
        rootController.didMove(toParent: self)

        self.view.addSubview(rootController.view)
        rootController.view.translatesAutoresizingMaskIntoConstraints = false
        rootController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        rootController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        rootController.view.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        rootController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }
    
}


#endif
