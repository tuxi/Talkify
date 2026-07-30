//
//  RuntimePairingScannerView.swift
//  Talkify
//
//  Runtime Sharing — iPhone QR scanner and pairing flow.
//

#if os(iOS)

import SwiftUI
import AgentKit
import AVFoundation

// MARK: - Scanner View

struct RuntimePairingScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    let onPaired: (RuntimeServerConnection) -> Void

    @State private var scannerModel = ScannerModel()
    @State private var decodedInvitation: RuntimePairingInvitation?
    @State private var decodeError: String?
    @State private var isPairing = false
    @State private var pairingError: String?
    @State private var bonjourBrowser = RuntimeBonjourBrowser()
    @State private var resolvedEndpoint: URL?

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview always present — it connects to the session
                // before startRunning() and lights up automatically when ready.
                ScannerPreview(session: scannerModel.captureSession)
                    .ignoresSafeArea()

                if scannerModel.cameraNotAvailable {
                    // Permission denied
                    Color.black.opacity(0.9).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("无法访问摄像头")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("请在「设置 > 隐私与安全性 > 相机」中允许 Talkify 访问摄像头")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("打开设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                } else if !scannerModel.isSessionReady {
                    // Session configuring — spinner overlay on top of preview
                    Color.black.opacity(0.92).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.2)
                        Text("正在启动摄像头...")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                } else {
                    // Scan targeting overlay (on top of live preview)
                    VStack {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(.white)
                            Text("将二维码置于取景框内")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                            Text("扫描 Mac Talkify 上显示的配对二维码")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.bottom, 80)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .onChange(of: scannerModel.scannedCode) { _, code in
                guard let code, decodedInvitation == nil else { return }
                handleScannedCode(code)
            }
        }
        .task {
            scannerModel.start()
        }
        .sheet(item: $decodedInvitation) { invitation in
            pairConfirmationSheet(invitation: invitation)
        }
    }

    // MARK: - Scan Handling

    private func handleScannedCode(_ code: String) {
        decodeError = nil
        do {
            let invitation = try RuntimePairingInvitation.decode(payload: code)
            // Validate expiry
            guard invitation.bootstrapExpiresAt > Date() else {
                decodeError = "此二维码已过期，请在 Mac 上重新生成。"
                scannerModel.resetScanAfterDelay()
                return
            }
            decodedInvitation = invitation
            // Start Bonjour discovery to resolve the endpoint
            bonjourBrowser.start()
            checkBonjourForInvitation(invitation)
        } catch {
            decodeError = error.localizedDescription
            scannerModel.resetScanAfterDelay()
        }
    }

    private func checkBonjourForInvitation(
        _ invitation: RuntimePairingInvitation
    ) {
        Task {
            // Give Bonjour a few seconds to discover
            try? await Task.sleep(for: .seconds(3))
            bonjourBrowser.stop()

            // Try to find matching Bonjour service
            if let match = bonjourBrowser.servers.first(where: {
                $0.serviceName == invitation.serviceName
                    && $0.port == invitation.port
            }),
            let endpoint = match.endpoint {
                resolvedEndpoint = endpoint
            }
        }
    }

    // MARK: - Pair Confirmation Sheet

    private func pairConfirmationSheet(
        invitation: RuntimePairingInvitation
    ) -> some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)

                Text("配对 Mac Runtime")
                    .font(.system(size: 20, weight: .semibold))

                Text(invitation.serverDisplayName)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)

            // Details
            VStack(alignment: .leading, spacing: 14) {
                confirmationRow(
                    "服务器",
                    invitation.serverDisplayName
                )
                confirmationRow(
                    "Server ID",
                    String(invitation.serverID.prefix(16)) + "…"
                )
                confirmationRow(
                    "地址",
                    "https://\(invitation.fallbackHost):\(invitation.port)"
                )
                if let endpoint = resolvedEndpoint {
                    confirmationRow(
                        "已通过 Bonjour 发现",
                        endpoint.absoluteString
                    )
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text("连接将通过证书固定 (SPKI pinning) 加密，无需安装根证书。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    Color.green.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .padding(.horizontal, 24)

            if let pairingError {
                Text(pairingError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            // Actions
            HStack(spacing: 12) {
                Button("取消") {
                    decodedInvitation = nil
                    scannerModel.resetScanAfterDelay()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Task { await performPairing(invitation) }
                } label: {
                    HStack(spacing: 6) {
                        if isPairing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isPairing ? "正在配对…" : "配对")
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isPairing)
            }
            .padding(.vertical, 20)
        }
        .background(Color.platformRuntimeEditorBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func confirmationRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    // MARK: - Pairing

    private func performPairing(
        _ invitation: RuntimePairingInvitation
    ) async {
        guard !isPairing else { return }
        isPairing = true
        pairingError = nil
        do {
            let deviceName = await UIDevice.current.name
            let connection = try await container.runtimeServers
                .pairSharedRuntime(
                    invitation: invitation,
                    resolvedEndpoint: resolvedEndpoint,
                    deviceName: deviceName
                )
            onPaired(connection)
            dismiss()
        } catch {
            pairingError = error.localizedDescription
        }
        isPairing = false
    }
}

// MARK: - RuntimePairingInvitation Identifiable

extension RuntimePairingInvitation: @retroactive Identifiable {
    public var id: String { serverID + ":" + bootstrapSecret }
}

// MARK: - AV Scanner Model

@Observable
final class ScannerModel: NSObject, @unchecked Sendable {
    private(set) var scannedCode: String?
    private(set) var isSessionReady = false
    private(set) var cameraNotAvailable = false

    @ObservationIgnored let captureSession = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "com.talkify.pairing-scanner",
        qos: .userInitiated
    )
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var setupStarted = false

    func start() {
        guard !setupStarted else { return }
        setupStarted = true
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupSession()
                } else {
                    Task { @MainActor in
                        self?.cameraNotAvailable = true
                    }
                }
            }
        case .denied, .restricted:
            Task { @MainActor in
                cameraNotAvailable = true
            }
        @unknown default:
            Task { @MainActor in
                cameraNotAvailable = true
            }
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.captureSession.canAddInput(input) else {
                self.captureSession.commitConfiguration()
                Task { @MainActor in self.cameraNotAvailable = true }
                return
            }
            self.captureSession.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard self.captureSession.canAddOutput(output) else {
                self.captureSession.commitConfiguration()
                Task { @MainActor in self.cameraNotAvailable = true }
                return
            }
            self.captureSession.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
            Task { @MainActor in
                self.isSessionReady = true
            }
        }
    }

    func resetScanAfterDelay() {
        resetTask?.cancel()
        resetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.scannedCode = nil
        }
    }
}

extension ScannerModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }
        Task { @MainActor [weak self] in
            self?.scannedCode = code
        }
    }
}

// MARK: - Camera Preview

// MARK: - Camera Preview (Fixed)

private struct ScannerPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // 如果 Session 发生变更，重新绑定
        if uiView.previewLayer.session != session {
            uiView.previewLayer.session = session
        }
    }
}

/// 自定义 UIView，利用 layoutSubviews 自动响应尺寸变化并同步 previewLayer
private final class VideoPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer class.")
        }
        return layer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // 确保 bounds 改变（如旋转、布局生效）时自动更新视频渲染区域
        previewLayer.frame = bounds
    }
}

#endif
