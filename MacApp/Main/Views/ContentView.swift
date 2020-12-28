//
//  ContentView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

struct ContentView: View {
    @State var selectedSection: MainSection?
    @State var sections: [MainSection] = []
    @State var isLoading: Bool = true
    var body: some View {
        NavigationView {
            if isLoading == true {
                if #available(OSX 11.0, *) {
                    ProgressView()
                } else {
                    
                }
            }
            else {
                // 在左侧菜单栏新增三个主入口
                List(selection: $selectedSection) {
                    ForEach(sections) { section in
                        NavigationLink(destination: PersonalCenterView()) {
                            Text(section.name)
                        }
                        .tag(section)
                    }
                }
                .listStyle(SidebarListStyle())
                .frame(minWidth: 70, idealWidth: 150, maxWidth: 200, maxHeight: .infinity)
                
    //            Text("请先选择左侧的栏目")
    //                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                if let selectedSection = self.selectedSection {
                    PersonalCenterView()
                }
            }
        }
        .onAppear() {
            loadData()
        }
    }
    
    
    var index: Int? {
        sections.firstIndex(where: { $0.id == selectedSection?.id })
    }
    
    var title: String {
        return selectedSection?.name ?? "主窗口"
    }
    
    func loadData() {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 3) {
            self.isLoading = false
            sections = [
                MainSection(name: "个人中心"),
                MainSection(name: "设置"),
                MainSection(name: "评价")
            ]
            self.selectedSection = sections.first
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(Prefs())
    }
}

