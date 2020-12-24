//
//  PersonalCenterView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/23.
//

import SwiftUI

struct PersonalCenterView: View {
    @State private var sidebarSections: [SidebarSection] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sidebarSections) { section in
                    Section(header: SidebarSectionHeaderView(section: section)) {
                        ForEach(section.items) { item in
                            NavigationLink(destination: MyCourseListView(model: item, items: [
                                MyCourse(name: "教孩子学习编程", content: "熬过了青葱岁月，走过了懵懂之约，是否可以共赏阳春白雪。", progress: 1.0),
                                MyCourse(name: "enba", content: "如果我的至尊宝成了别人的齐天大圣，那就炸了他的花果山。", progress: 1.0),
                                MyCourse(name: "enba", content: "都记住啦，酒能解决的事，绝不能浪费眼泪。", progress: 1.0),
                            ])) {
                                SidebarTableRowView(model: item)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 80, maxWidth: 350)
            
        }
        .listStyle(SidebarListStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: {
            self.loadData()
        })
        
        
    }
    
    private func loadData() {
        var items = [SidebarSectionItem]()
        items.append(SidebarSectionItem(title: "我的课程", icon: "icon_mine_Invite_friends"))
        items.append(SidebarSectionItem(title: "我的项目", icon: "icon_mine_Invite_friends"))
        items.append(SidebarSectionItem(title: "直播室课程", icon: "icon_mine_Invite_friends"))
        items.append(SidebarSectionItem(title: "个人资料", icon: "icon_mine_Invite_friends"))
        
        sidebarSections = [SidebarSection(title: "小明", icon: "Icon_xile_logo", items: items)]
    }
}

struct SidebarSectionHeaderView: View {
    let section: SidebarSection
    
    var body: some View {
        VStack {
            Image(section.icon)
                .resizable()
                .frame(width: 80, height: 80)
                .aspectRatio(contentMode: .fill)
                .cornerRadius(40.0)
            Spacer()
            
            Text(section.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
    }
}

struct PersonalCenterView_Previews: PreviewProvider {
    static var previews: some View {
        PersonalCenterView()
        
    }
}


struct SidebarTableRowView: View {
    let model: SidebarSectionItem
    
    var body: some View {
        HStack(spacing: 10) {
            Image(model.icon)
                .resizable()
                .frame(width: 15, height: 15)
                .aspectRatio(contentMode: .fit)
            Text(model.title)
                .frame(maxWidth: 150, alignment: .leading)
                .font(.headline)
                .foregroundColor(.secondary)
                .truncationMode(.tail)
            
            Spacer()
        }
    }
    
}
