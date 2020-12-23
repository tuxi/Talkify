//
//  ContentView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

struct ContentView: View {
    @State var selections: Set<Int> = [0,1,2]
    var body: some View {
        NavigationView {
            // 在左侧菜单栏新增三个主入口
            List(selection: $selections) {
                NavigationLink(destination: PersonalCenterView()) {
                    Text("个人中心")
                }
                .tag(0)
                NavigationLink(destination: PersonalCenterView()) {
                    Text("排行")
                }
                .tag(1)
                NavigationLink(destination: PersonalCenterView()) {
                    Text("评价")
                }
                .tag(2)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 70, idealWidth: 150, maxWidth: 200, maxHeight: .infinity)
            
            Text("请先选择左侧的栏目")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

