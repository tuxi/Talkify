//
//  LoginView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/23.
//

import SwiftUI

struct LoginView: View {
    @State var password: String = ""
    var body: some View {
        VStack {
            Text("登陆")
                .padding()
            Image("Icon_xile_logo")
                .padding()
            HStack {
                Spacer()
                HStack(spacing: 10.0) {
                    Spacer()
                    Image("icon_mine_Invite_friends")
                    SecureField("请输入密码", text: $password) {
                        
                    }
                    Spacer()
                }
                .frame(height: 45, alignment: .center)
                .cornerRadius(30)
                .border(Color.gray, width: 0.5)
                Spacer()
            }
            .padding()
            HStack {
                Spacer()
                Button("登陆") {
                    
                }
                Spacer()
            }
        }
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
