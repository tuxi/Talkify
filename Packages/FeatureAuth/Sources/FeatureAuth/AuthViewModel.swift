//
//  AuthViewModel.swift
//  FeatureAuth
//
//  Created by xiaoyuan on 2026/3/1.
//

import Foundation
import Observation
import SwiftUI
import CoreKit
#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
public final class AuthViewModel {
    private let service: AuthService
    let manager: AuthManager
    let userManager: UserManager
    private let store = UserDefaults.standard
    private let environment: AppEnvironment
    private let lastLoginContextKeyPrefix = "com.objc.talkify.v2.lastLoginContext"
    
    var phoneNumber: String = ""
    var captcha: String = ""
    var isLogging: Bool = false
    var isSendingCode: Bool = false
    var errorMessage: String?
    var selectedLoginMethod: LoginMethod = .phoneCode

    var isOneTapAvailable = false
    var isOneTapLogging = false
    var showSmsLogin = false

    var timerCount = 60
    var isCountingDown = false
    @ObservationIgnored
    private var timer: Timer?

    public init(
        service: AuthService,
        manager: AuthManager,
        userManager: UserManager,
        environment: AppEnvironment = .prod
    ) {
        self.service = service
        self.manager = manager
        self.userManager = userManager
        self.environment = environment
        restoreLastLoginContext()
    }
    
    func login(colorScheme: ColorScheme = .light) async {
        if useOneTapLogin {
            await performOneTapLogin(colorScheme: colorScheme)
        } else {
            await loginByPhoneCode()
        }
    }

    var useOneTapLogin: Bool {
        supportsOneTapLogin && isOneTapAvailable && !showSmsLogin
    }

    var supportsOneTapLogin: Bool {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        return true
        #else
        return false
        #endif
    }

    func checkOneTapAvailability() async {
        guard supportsOneTapLogin else { return }
        isOneTapAvailable = await OneTapLoginService.shared.checkAvailability()
    }

    func performOneTapLogin(colorScheme: ColorScheme = .light) async {
        guard !isOneTapLogging else { return }
        isOneTapLogging = true
        errorMessage = nil

        await OneTapLoginService.shared.preWarm()

        OneTapLoginService.shared.startLoginPage(
            colorScheme: colorScheme,
            onSuccess: { [weak self] token in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.loginByOneTap(accessToken: token)
                    self.isOneTapLogging = false
                }
            },
            onSwitch: { [weak self] in
                self?.isOneTapLogging = false
                self?.showSmsLogin = true
                OneTapLoginService.shared.dismiss()
            },
            onCancel: { [weak self] in
                self?.isOneTapLogging = false
            }
        )
        // startLoginPage returns immediately; isOneTapLogging is cleared inside each callback.
    }

    func sendPhoneCode() {
        guard !isSendingCode, validatePhoneNumber() else {
            if !validatePhoneNumber() {
                errorMessage = TalkifyLocalized.string("auth.invalid_phone")
            }
            return
        }
        
        isSendingCode = true
        errorMessage = nil
        
        Task {
            defer { isSendingCode = false }
            
            do {
                _ = try await service.sendPhoneCode(phone: phoneNumber)
                startCountdown()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    
    func loginByPhoneCode() async {
        guard validatePhoneNumber() else {
            errorMessage = TalkifyLocalized.string("auth.invalid_phone")
            return
        }
        guard validateCaptcha() else {
            errorMessage = TalkifyLocalized.string("auth.empty_code")
            return
        }
        
        isLogging = true
        errorMessage = nil
        
        do {
            let response = try await service.loginByPhoneCode(phone: phoneNumber, code: captcha)
            completeLogin(response, method: .phoneCode, phoneNumber: phoneNumber)
            _ = try? await userManager.fetchProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLogging = false
    }
    
    func loginByOneTap(accessToken: String, outId: String? = nil) async {
        guard !accessToken.isEmpty else {
            errorMessage = TalkifyLocalized.string("auth.onetap_invalid")
            return
        }
        
        isLogging = true
        errorMessage = nil
        
        do {
            let response = try await service.loginByOneTap(accessToken: accessToken, outId: outId)
            completeLogin(response, method: .phoneOneTap, phoneNumber: phoneNumber.nilIfEmpty)
            _ = try? await userManager.fetchProfile()
        } catch {
            errorMessage = error.localizedDescription
            OneTapLoginService.shared.dismiss()
        }
        
        isLogging = false
    }
    
    func loginByApple(
        identityToken: String,
        authorizationCode: String,
        email: String? = nil,
        givenName: String? = nil,
        familyName: String? = nil
    ) async {
        guard !identityToken.isEmpty, !authorizationCode.isEmpty else {
            errorMessage = TalkifyLocalized.string("auth.apple_invalid")
            return
        }
        
        isLogging = true
        errorMessage = nil
        
        do {
            let response = try await service.loginByApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode,
                email: email,
                givenName: givenName,
                familyName: familyName
            )
            completeLogin(response, method: .apple, phoneNumber: phoneNumber.nilIfEmpty)
            _ = try? await userManager.fetchProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLogging = false
    }
    
    func startTimer() {
        sendPhoneCode()
    }

    func sanitizePhoneNumberInput() {
        var digits = phoneNumber.filter(\.isNumber)
        if digits.count > 11, digits.hasPrefix("86") {
            digits.removeFirst(2)
        }
        if digits != phoneNumber {
            phoneNumber = digits
        }
        if phoneNumber.count > 11 {
            phoneNumber = String(phoneNumber.prefix(11))
        }
    }

    func sanitizeCaptchaInput() {
        let digits = captcha.filter(\.isNumber)
        if digits != captcha {
            captcha = digits
        }
        if captcha.count > 6 {
            captcha = String(captcha.prefix(6))
        }
    }

    func requireAgreement(accepted: Bool) -> Bool {
        guard accepted else {
            errorMessage = TalkifyLocalized.string("auth.agreement_required")
            return false
        }
        return true
    }

    var canSendCode: Bool {
        validatePhoneNumber() && !isSendingCode && !isLogging
    }

    var canSubmitPhoneLogin: Bool {
        validatePhoneNumber() && validateCaptcha() && !isLogging
    }
    
    private func startCountdown() {
        timer?.invalidate()
        isCountingDown = true
        timerCount = 60
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let shouldInvalidate = MainActor.assumeIsolated { () -> Bool in
                if self.timerCount <= 1 {
                    self.timerCount = 0
                    self.isCountingDown = false
                    return true
                } else {
                    self.timerCount -= 1
                    return false
                }
            }
            
            if shouldInvalidate {
                timer.invalidate()
            }
        }
    }
    
    private func completeLogin(_ token: AuthToken, method: LoginMethod, phoneNumber: String?) {
        manager.updateLoginState(token: token)
        persistLastLoginContext(method: method, phoneNumber: phoneNumber)
        selectedLoginMethod = method
    }
    
    private func validatePhoneNumber() -> Bool {
        phoneNumber.count == 11 && phoneNumber.allSatisfy(\.isNumber)
    }
    
    private func validateCaptcha() -> Bool {
        !captcha.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func persistLastLoginContext(method: LoginMethod, phoneNumber: String?) {
        let context = LastLoginContext(
            method: method,
            phoneNumber: phoneNumber?.nilIfEmpty,
            lastLoginAt: Date()
        )
        
        if let data = try? JSONEncoder().encode(context) {
            store.set(data, forKey: lastLoginContextKey)
        }
    }
    
    private func restoreLastLoginContext() {
        guard let data = store.data(forKey: lastLoginContextKey),
              let context = try? JSONDecoder().decode(LastLoginContext.self, from: data) else {
            return
        }
        
        selectedLoginMethod = context.method
        if let phoneNumber = context.phoneNumber {
            self.phoneNumber = phoneNumber
        }
    }

    private var lastLoginContextKey: String {
        "\(lastLoginContextKeyPrefix).\(environment.rawValue)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
