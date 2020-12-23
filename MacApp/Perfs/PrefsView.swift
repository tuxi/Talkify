//
//  PrefsView.swift
//  MacApp
//
//  Created by xiaoyuan on 2020/12/22.
//

import SwiftUI

struct PrefsView: View {
    
    @ObservedObject var prefs: Prefs
    @State var prefsWindowDelegate = PrefsWindowDelegate()
    
    var body: some View {
        VStack {
            Toggle(isOn: $prefs.showCopyright, label: {
                Text("Show Copyright Notice")
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var window: NSWindow!
    init(prefs: Prefs) {
        self.prefs = prefs
        window = NSWindow.createStandardWindow(WithTitle: "Preferences", width: 300, height: 100)
        window.contentView = NSHostingView(rootView: self)
        window.delegate = prefsWindowDelegate
        window.tabbingMode = .disallowed
        window.makeKeyAndOrderFront(nil)
    }
    
    class PrefsWindowDelegate: NSObject, NSWindowDelegate {
        var windowIsOpen = false
        
        func windowWillClose(_ notification: Notification) {
            windowIsOpen = false
        }
    }
}

struct PrefsView_Previews: PreviewProvider {
    static var previews: some View {
        PrefsView(prefs: Prefs())
    }
}
