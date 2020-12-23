//
//  UserDefaultsPropertyWrapper.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//  from https://www.avanderlee.com/swift/property-wrappers/

import Foundation

@propertyWrapper
struct UserDefault<T> {
    let key: String
    let defaultValue: T
    init(_ key: String, defaultValue: T) {
        self.key = key
        self.defaultValue = defaultValue
    }
    
    var wrappedValue: T {
        get {
            return UserDefaults.standard.object(forKey: key) as? T ?? defaultValue
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
    
}
