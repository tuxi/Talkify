//
//  DLLog.swift
//  CoreKit
//
//  Created by xiaoyuan on 2026/4/26.
//

import Foundation

/// 自定义日志打印方法
/// - Parameters:
///   - message: 打印的内容
///   - file: 默认参数，获取调用处的文件路径
///   - method: 默认参数，获取调用处的方法名
///   - line: 默认参数，获取调用处的行号
/// -  DLLog("开始检测主体", image.size, "其他信息")
public func DLLog(_ items: Any...,
           file: String = #file,
           method: String = #function,
           line: Int = #line) {
#if DEBUG
    let fileName = (file as NSString).lastPathComponent
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let time = formatter.string(from: Date())
    
    // 将多个参数合并成一个字符串，用空格分隔
    let message = items.map { "\($0)" }.joined(separator: " ")
    
    print("\(time) [\(fileName):\(line)] \(method) -> \(message)\n")
#endif
}
