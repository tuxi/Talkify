//
//  DetailView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

struct DetailView: View {
    let model: SidebarSectionItem
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct DetailView_Previews: PreviewProvider {
    static var previews: some View {
        DetailView(model: SidebarSectionItem(title: "Hello world!", icon: "Icon_xile_logo"))
    }
}
