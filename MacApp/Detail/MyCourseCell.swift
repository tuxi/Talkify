//
//  MyCourseCell.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/24.
//

import SwiftUI

struct MyCourseCell: View {
    @State var model: MyCourse
    var colors = [
        Color.red,
        Color.orange,
        Color.yellow,
        Color.green,
        Color.blue,
        Color.purple
    ]
    var body: some View {
        HStack(alignment: .top, spacing: 12, content: {
            Image("avater")
                .resizable()
                .frame(width: 100, height: 100, alignment: .center)
                .foregroundColor(colors.randomElement())
                .opacity(0.7)
                .font(.system(size: 40))
                .aspectRatio(contentMode: .fit)
            
        
            VStack(alignment: .leading, spacing: 2, content: {
                HStack(alignment: .firstTextBaseline, content: {
                    Text(model.name)
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                    
                    Text("@username")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text(" 9:41 AM")
                        .font(.body)
                        .foregroundColor(.secondary)
                })
                
                Text(model.content)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                if #available(OSX 11.0, *) {
                    ProgressView(value: model.progress)
                        .padding(.trailing)
                } else {
                    // Fallback on earlier versions
                }
                
                Text("2020-11-22 22:12:30")
                
                HStack(alignment: .center, spacing: 0, content: {
                    Spacer()
                    Button("想继续学习") {
                        
                    }
                    .padding(.trailing)
                })
                .padding(.bottom)
            })
        })
    }
}

struct MyCourseCell_Previews: PreviewProvider {
    static var previews: some View {
        MyCourseCell(model: MyCourse(name: "教孩子学习Python 课程", content: "让孩子能够快速学习Python 课程", progress: 0.8))
    }
}
