//
//  MyCourseListView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

struct MyCourseListView: View {
    let model: SidebarSectionItem
    @State var items: [MyCourse] = []
    @State var showComposeWindow = false
    var body: some View {
        if #available(OSX 11.0, *) {
            Feed(items: items)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("我的课堂")
                .background(Color.white)
                .toolbar(content: {
                    ToolbarItem(placement: .status) {
                        Button(action: { self.showComposeWindow = true }, label: {
                            Image(systemName: "square.and.pencil")
                        })
                        .popover(isPresented: $showComposeWindow, content: {
                            Compose(showComposeWindow: $showComposeWindow)
                        })
                    }
                })
        } else {
            Feed(items: items)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Feed: View {
    @State var items: [MyCourse] = []
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(items, id: \.self) { item in
                    MyCourseCell(model: item)
                        .padding()
                    Divider()
                }
            }
        }
    }
}

struct Compose: View {
    @Binding var showComposeWindow: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if #available(OSX 11.0, *) {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundColor(Color("AccentColor"))
                        .opacity(0.7)
                        .font(.system(size: 40))
                } else {
                    Image("avater")
                }
                Text("What's happening?")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            
            Spacer()
            
            Divider()
        }
        .frame(width: 256, height: 192)
    }
}


struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        MyCourseListView(model: SidebarSectionItem(title: "Hello world!", icon: "Icon_xile_logo"), items: [
            MyCourse(name: "enba", content: "熬过了青葱岁月，走过了懵懂之约，是否可以共赏阳春白雪。", progress: 1.0),
            MyCourse(name: "enba", content: "如果我的至尊宝成了别人的齐天大圣，那就炸了他的花果山。", progress: 1.0),
            MyCourse(name: "enba", content: "都记住啦，酒能解决的事，绝不能浪费眼泪。", progress: 1.0),
        ])
    }
}
