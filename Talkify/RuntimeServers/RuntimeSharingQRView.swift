//
//  RuntimeSharingQRView.swift
//  Talkify
//
//  Runtime Sharing — QR code display for pairing invitation.
//

#if os(macOS)

import SwiftUI
import Combine
import AgentKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct RuntimeSharingQRView: View {
    let invitation: RuntimePairingInvitation
    let payload: String
    let onDismiss: () -> Void

    @State private var timeRemaining: TimeInterval = 0
    @State private var qrImage: CGImage?

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 440, idealWidth: 440, minHeight: 580)
        .background(Color.platformRuntimeEditorBackground)
        .task {
            generateQR()
            updateTimeRemaining()
        }
        .onReceive(timer) { _ in updateTimeRemaining() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "qrcode")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(
                    Color.accentColor.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("配对二维码")
                    .font(.system(size: 18, weight: .semibold))
                Text("\(invitation.serverDisplayName) · 有效期 \(formattedTimeRemaining)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 24) {
            if let qrImage {
                qrCodeView(qrImage)
            } else {
                ProgressView("生成二维码…")
                    .padding(.vertical, 40)
            }

            serverInfo

            HStack(spacing: 12) {
                Button {
                    onDismiss()
                } label: {
                    Text("完成")
                        .frame(minWidth: 80)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.bottom, 4)
        }
        .padding(24)
    }

    // MARK: - QR Code

    private func qrCodeView(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1.0)
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
            .frame(width: 220, height: 220)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if timeRemaining <= 0 {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.6))
                    VStack(spacing: 8) {
                        Image(systemName: "hourglass.bottomhalf.filled")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                        Text("已过期")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("请关闭后重新生成")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
    }

    // MARK: - Server Info

    private var serverInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("服务器", invitation.serverDisplayName)
            infoRow("Server ID", String(invitation.serverID.prefix(12)) + "…")
            infoRow("地址", "https://\(invitation.fallbackHost):\(invitation.port)")
            infoRow("SPKI 指纹", String(invitation.spkiSHA256.prefix(16)) + "…")

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11))
                    .padding(.top, 1)
                Text("扫描此二维码的 iPhone 将通过证书固定建立加密连接，无需安装根证书。二维码仅在 \(formattedTimeRemaining) 内有效。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.accentColor.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 12))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }

    // MARK: - Logic

    private func generateQR() {
        guard qrImage == nil, let data = payload.data(using: .utf8) else { return }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return }
        let context = CIContext()
        let extent = output.extent
        guard extent.width > 0, extent.height > 0 else { return }
        let scale: CGFloat = 8
        let transformed = output.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )
        qrImage = context.createCGImage(transformed, from: transformed.extent)
    }

    private func updateTimeRemaining() {
        timeRemaining = max(0, invitation.bootstrapExpiresAt.timeIntervalSinceNow)
    }

    private var formattedTimeRemaining: String {
        guard timeRemaining > 0 else { return "已过期" }
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        if minutes > 0 {
            return "\(minutes) 分 \(seconds) 秒"
        }
        return "\(seconds) 秒"
    }
}

#endif
