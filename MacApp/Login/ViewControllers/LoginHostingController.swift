//
//  LoginHostingController.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/23.
//

import SwiftUI

class LoginHostingController: NSHostingController<LoginView> {

    override init(rootView: LoginView) {
        super.init(rootView: rootView)
    }
    
    @objc required dynamic init?(coder: NSCoder) {
        super.init(coder: coder, rootView: LoginView())
    }
}
