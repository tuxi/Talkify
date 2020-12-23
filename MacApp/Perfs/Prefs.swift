//
//  Prefs.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import Foundation

class Prefs: ObservableObject {
    
    @Published var showCopyright: Bool = UserDefaults.standard.bool(forKey: "showCopyright") {
        didSet {
            UserDefaults.standard.set(self.showCopyright, forKey: "showCopyright")
        }
    }
    
}
