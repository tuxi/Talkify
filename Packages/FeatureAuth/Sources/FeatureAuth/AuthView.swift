//
//  AuthView.swift
//  FeatureAuth
//

import SwiftUI
import CoreKit
import DesignKit
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// 与 CodeAgent 桌面端一致的认证入口。保持认证提供商的真实品牌呈现：
/// Apple 使用系统授权控件，手机验证码沿用现有 Gateway 登录流程。
public struct AuthView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var viewModel: AuthViewModel
    @State private var isAgreementAccepted = true
    @State private var agreementURL: URL?
    @FocusState private var focusedField: Field?

    private enum Field { case phone, captcha }

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            authBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 70)

                    VStack(spacing: 12) {
                        Text("登录")
                            .font(.system(size: 40, weight: .bold, design: .serif))
                        Text("登录后即可继续使用 CodeAgent")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }

                    authCard
                        .padding(.top, 58)

                    agreementRow
                        .padding(.top, 22)
                        .frame(maxWidth: 540)

                    Spacer(minLength: 70)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, minHeight: 650)
            }
        }
        #if os(macOS)
        .frame(minWidth: 760, minHeight: 680)
        #endif
        .onChange(of: viewModel.phoneNumber) { _, _ in viewModel.sanitizePhoneNumberInput() }
        .onChange(of: viewModel.captcha) { _, _ in viewModel.sanitizeCaptchaInput() }
        .onAppear { Task { await viewModel.checkOneTapAvailability() } }
        .sheet(item: $agreementURL) { url in
            NavigationStack {
                BrowserView(url: url)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
#if os(macOS)
            return .systemAction // MacOS 打开浏览器
#else
            agreementURL = url // iOS 使用app内浏览器BrowserView
            return .handled
#endif
        })
    }
}

private extension AuthView {
    var authBackground: some View {
        ZStack {
            Color.systemBackground.ignoresSafeArea()
            Circle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.025))
                .frame(width: 580, height: 580)
                .blur(radius: 75)
                .offset(x: -360, y: 300)
            Circle()
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.045))
                .frame(width: 480, height: 480)
                .blur(radius: 95)
                .offset(x: 330, y: -270)
        }
    }

    var authCard: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage, !errorMessage.isEmpty {
                errorBanner(errorMessage)
                    .padding(.bottom, 18)
            }

            #if canImport(AuthenticationServices)
            appleSignInButton
            #endif

            dividerTitle("或")
                .padding(.vertical, 26)

            VStack(spacing: 14) {
                phoneField
                codeField
                continueButton
            }
        }
        .padding(56)
        .frame(maxWidth: 600)
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.82))
                .overlay {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 32, x: 0, y: 16)
    }

    #if canImport(AuthenticationServices)
    var appleSignInButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleAppleLogin(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .whiteOutline : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("使用 Apple 继续")
    }
    #endif

    var phoneField: some View {
        HStack(spacing: 12) {
            Text("+86")
                .font(.system(size: 16, weight: .semibold))
            Divider().frame(height: 22)
            TextField("输入手机号", text: $viewModel.phoneNumber)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.telephoneNumber)
                #endif
                .focused($focusedField, equals: .phone)
        }
        .authTextFieldStyle()
    }

    var codeField: some View {
        HStack(spacing: 12) {
            TextField("输入验证码", text: $viewModel.captcha)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                #if os(iOS)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                #endif
                .focused($focusedField, equals: .captcha)

            Button(action: sendPhoneCode) {
                Text(viewModel.isCountingDown ? "\(viewModel.timerCount)s" : (viewModel.isSendingCode ? "发送中" : "获取验证码"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(viewModel.canSendCode ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSendCode || viewModel.isCountingDown)
        }
        .authTextFieldStyle()
    }

    var continueButton: some View {
        Button(action: loginWithPhoneCode) {
            HStack(spacing: 8) {
                if viewModel.isLogging { ProgressView().controlSize(.small) }
                Text(viewModel.isLogging ? "登录中…" : "使用手机号继续")
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmitPhoneLogin)
        .opacity(viewModel.canSubmitPhoneLogin ? 1 : 0.42)
    }

    var agreementRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $isAgreementAccepted)
                .toggleStyle(AgreementToggleStyle())
            Text(agreementAttributedText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
            Spacer(minLength: 0)
        }
    }

    var agreementAttributedText: AttributedString {
        var text = AttributedString("继续即表示你已阅读并同意 ")
        var terms = AttributedString("《用户协议》")
        terms.link = AgreementURLs.terms
        terms.foregroundColor = .accentColor
        var joiner = AttributedString(" 与 ")
        var privacy = AttributedString("《隐私政策》")
        privacy.link = AgreementURLs.privacy
        privacy.foregroundColor = .accentColor
        text.append(terms)
        text.append(joiner)
        text.append(privacy)
        return text
    }

    func dividerTitle(_ title: String) -> some View {
        HStack(spacing: 14) {
            Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Rectangle().fill(Color.primary.opacity(0.11)).frame(height: 1)
        }
    }

    func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func sendPhoneCode() {
        guard viewModel.requireAgreement(accepted: isAgreementAccepted) else { return }
        viewModel.sendPhoneCode()
        if viewModel.validatePhoneForFocusAdvance { focusedField = .captcha }
    }

    func loginWithPhoneCode() {
        guard viewModel.requireAgreement(accepted: isAgreementAccepted) else { return }
        Task { await viewModel.login() }
    }

    #if canImport(AuthenticationServices)
    func handleAppleLogin(_ result: Result<ASAuthorization, any Error>) {
        guard viewModel.requireAgreement(accepted: isAgreementAccepted) else { return }
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let codeData = credential.authorizationCode,
                  let token = String(data: tokenData, encoding: .utf8),
                  let code = String(data: codeData, encoding: .utf8) else {
                viewModel.errorMessage = "Apple 登录凭证解析失败"
                return
            }
            Task {
                await viewModel.loginByApple(
                    identityToken: token,
                    authorizationCode: code,
                    email: credential.email,
                    givenName: credential.fullName?.givenName,
                    familyName: credential.fullName?.familyName
                )
            }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }
    #endif
}

private extension AuthViewModel {
    var validatePhoneForFocusAdvance: Bool { phoneNumber.count == 11 }
}

private struct AgreementToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(configuration.isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func authTextFieldStyle() -> some View {
        self
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
