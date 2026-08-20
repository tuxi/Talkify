//
//  RuntimeSharedDevicesView.swift
//  Talkify
//
//  Runtime Sharing — Paired device management.
//

#if os(macOS)

import SwiftUI
import AgentKit

struct RuntimeSharedDevicesView: View {
    @Environment(\.dismiss) private var dismiss

    let devices: [RuntimeSharedDevice]
    let onRevoke: (String) -> Void

    @State private var pendingRevokeDeviceID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Color.accentColor.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("已配对设备")
                        .font(.system(size: 18, weight: .semibold))
                    let active = devices.filter { $0.revokedAt == nil }.count
                    Text(
                        active > 0
                            ? "\(active) 台设备已连接"
                            : "暂无已配对的设备"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
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

            Divider()

            // Content
            if devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("尚未有设备通过二维码配对到此 Mac")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(devices) { device in
                            deviceRow(device)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 200)
            }

            Divider()

            // Footer
            HStack {
                Text("撤销设备会立即断开其连接。已撤销的设备可以保留记录以供审计。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 380)
        .background(Color.platformRuntimeEditorBackground)
        .alert("撤销设备？", isPresented: Binding(
            get: { pendingRevokeDeviceID != nil },
            set: { if !$0 { pendingRevokeDeviceID = nil } }
        ), presenting: pendingRevokeDeviceID) { deviceID in
            Button("取消", role: .cancel) {
                pendingRevokeDeviceID = nil
            }
            Button("撤销", role: .destructive) {
                onRevoke(deviceID)
                pendingRevokeDeviceID = nil
            }
        } message: { deviceID in
            if let device = devices.first(where: { $0.deviceID == deviceID }) {
                Text("“\(device.displayName)”将立即断开连接。此操作不可撤销，但设备记录将保留。")
            }
        }
    }

    // MARK: - Device Row

    @ViewBuilder
    private func deviceRow(_ device: RuntimeSharedDevice) -> some View {
        let isRevoked = device.revokedAt != nil
        HStack(spacing: 14) {
            // Status indicator
            Circle()
                .fill(isRevoked ? Color.gray : Color.green)
                .frame(width: 9, height: 9)

            // Device icon
            Image(
                systemName: device.platform.lowercased().contains("ios")
                    ? "iphone" : "desktopcomputer"
            )
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.system(size: 14, weight: .medium))
                    .strikethrough(isRevoked)
                HStack(spacing: 8) {
                    Text(device.platform)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(
                        device.pairedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    if isRevoked, let revokedAt = device.revokedAt {
                        Text("· 已撤销")
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            if !isRevoked {
                Button {
                    pendingRevokeDeviceID = device.deviceID
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.02))
        )
        .padding(.vertical, 2)
    }

}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#endif
