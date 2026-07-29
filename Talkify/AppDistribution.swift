//
//  AppDistribution.swift
//  Talkify
//
//  Compile-time distribution policy for the two macOS release channels.
//

#if os(macOS) && !TALKIFY_MAC_APP_STORE && !TALKIFY_MAC_DIRECT
#error("macOS builds must use the Talkify-MacAppStore or Talkify-MacDirect scheme.")
#endif

enum AppDistribution: Sendable {
    case standard
    case macAppStore
    case macDirect

    static let current: AppDistribution = {
        #if os(macOS) && TALKIFY_MAC_APP_STORE
        return .macAppStore
        #elseif os(macOS) && TALKIFY_MAC_DIRECT
        return .macDirect
        #else
        return .standard
        #endif
    }()

    var supportsNativeAppleSignIn: Bool {
        self != .macDirect
    }
}
