//
//  ShareViewController.swift
//  TalkifyShareExtension
//
//  Created by Codex on 2026/7/22.
//

@preconcurrency import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let extensionItems = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem } ?? []
        let providers: [NSItemProvider] = extensionItems.reduce(into: []) { result, item in
            result.append(contentsOf: item.attachments ?? [])
        }
        let content = ShareImportView(
            providers: providers,
            onCancel: { [weak self] request in
                if let request { ShareInboxWriter.remove(request) }
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onFinish: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            },
            onContinue: { [weak self] request, workspaceName in
                guard let self else { throw ShareImportError.cannotOpenApp }
                try ShareInboxWriter.update(request, workspaceName: workspaceName)
                var components = URLComponents()
                components.scheme = "talkifyapp"
                components.host = "shared-import"
                components.queryItems = [URLQueryItem(name: "id", value: request.id)]
                guard let url = components.url,
                      let extensionContext = self.extensionContext
                else { throw ShareImportError.cannotOpenApp }

                return await withCheckedContinuation { continuation in
                    extensionContext.open(url) { [weak self] opened in
                        if opened {
                            self?.extensionContext?.completeRequest(returningItems: nil)
                        }
                        continuation.resume(returning: opened)
                    }
                }
            }
        )
        let host = UIHostingController(rootView: content)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}

private struct ShareImportView: View {
    let providers: [NSItemProvider]
    let onCancel: (ShareInboxWriter.Request?) -> Void
    let onFinish: () -> Void
    let onContinue: (ShareInboxWriter.Request, String) async throws -> Bool

    @State private var request: ShareInboxWriter.Request?
    @State private var workspaceName = ""
    @State private var errorMessage: String?
    @State private var isPreparing = true
    @State private var isContinuing = false
    @State private var requiresManualOpen = false

    private var trimmedName: String {
        workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if requiresManualOpen {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.green)
                        Text(TalkifyLocalized.string("share.materials_received"))
                            .font(.title2.bold())
                        Text(TalkifyLocalized.string("share.cannot_open_agent"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(TalkifyLocalized.string("common.action.done"), action: onFinish)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(28)
                } else if isPreparing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(TalkifyLocalized.string("share.receiving_materials"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let request {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                Text(TalkifyLocalized.string("share.create_workspace"))
                                    .font(.system(size: 23, weight: .bold, design: .rounded))
                                Text(TalkifyLocalized.string("share.workspace_desc"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            TextField(TalkifyLocalized.string("share.workspace_name"), text: $workspaceName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 46)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))

                            VStack(alignment: .leading, spacing: 7) {
                                Text(String(format: TalkifyLocalized.string("share.containing_items"), String(request.items.count)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(Array(request.items.enumerated()), id: \.offset) { _, item in
                                    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc")
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.vertical, 3)
                                }
                            }

                            if let errorMessage {
                                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button(action: continueInApp) {
                                HStack(spacing: 8) {
                                    if isContinuing { ProgressView().tint(.white) }
                                    Label(TalkifyLocalized.string("share.continue_in_agent"), systemImage: "arrow.up.forward.app.fill")
                                }
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15))
                            }
                            .buttonStyle(.plain)
                            .disabled(trimmedName.isEmpty || isContinuing)
                        }
                        .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        TalkifyLocalized.string("share.cannot_receive"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? TalkifyLocalized.string("share.no_readable_files"))
                    )
                }
            }
            .navigationTitle(TalkifyLocalized.string("share.send_to_agent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !requiresManualOpen {
                        Button(TalkifyLocalized.string("common.action.cancel")) { onCancel(request) }
                            .disabled(isContinuing)
                    }
                }
            }
        }
        .task { await prepare() }
    }

    @MainActor
    private func prepare() async {
        guard !providers.isEmpty else {
            isPreparing = false
            errorMessage = TalkifyLocalized.string("share.no_files_found")
            return
        }
        do {
            let prepared = try await ShareInboxWriter.prepare(providers: providers)
            request = prepared
            workspaceName = prepared.suggestedName
        } catch {
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    private func continueInApp() {
        guard let request, !trimmedName.isEmpty, !isContinuing else { return }
        isContinuing = true
        errorMessage = nil
        Task {
            do {
                let opened = try await onContinue(request, trimmedName)
                if !opened {
                    requiresManualOpen = true
                    isContinuing = false
                }
            } catch {
                errorMessage = error.localizedDescription
                isContinuing = false
            }
        }
    }
}

private enum ShareInboxWriter {
    static let appGroupID = "group.com.objc.chat"
    private static let inboxDirectoryName = "SharedImportInbox"
    private static let manifestName = "manifest.json"
    private static let payloadDirectoryName = "Payload"

    struct Request: Codable {
        let version: Int
        let id: String
        var suggestedName: String
        let createdAt: Date
        let items: [Item]
    }

    struct Item: Codable {
        let name: String
        let isDirectory: Bool
    }

    static func prepare(providers: [NSItemProvider]) async throws -> Request {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { throw ShareImportError.appGroupUnavailable }

        let inbox = container.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        let id = UUID().uuidString
        let requestDirectory = inbox.appendingPathComponent(id, isDirectory: true)
        let payload = requestDirectory.appendingPathComponent(payloadDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)

        do {
            var items: [Item] = []
            var lastError: Error?
            for provider in providers {
                do {
                    let item = try await copyRepresentation(from: provider, into: payload)
                    items.append(item)
                } catch {
                    lastError = error
                }
            }
            guard !items.isEmpty else { throw lastError ?? ShareImportError.noReadableItems }

            let suggestedName: String
            if items.count == 1 {
                let name = items[0].name
                suggestedName = items[0].isDirectory
                    ? name
                    : (name as NSString).deletingPathExtension
            } else {
                suggestedName = TalkifyLocalized.string("share.shared_materials")
            }
            let request = Request(
                version: 1,
                id: id,
                suggestedName: suggestedName.isEmpty ? TalkifyLocalized.string("share.shared_materials") : suggestedName,
                createdAt: .now,
                items: items
            )
            try write(request, to: requestDirectory)
            return request
        } catch {
            try? FileManager.default.removeItem(at: requestDirectory)
            throw error
        }
    }

    static func update(_ request: Request, workspaceName: String) throws {
        var updated = request
        updated.suggestedName = workspaceName
        try write(updated, to: requestDirectoryURL(for: request.id))
    }

    static func remove(_ request: Request) {
        try? FileManager.default.removeItem(at: requestDirectoryURL(for: request.id))
    }

    private static func copyRepresentation(
        from provider: NSItemProvider,
        into payload: URL
    ) async throws -> Item {
        let providerBox = ItemProviderBox(provider)
        guard let typeIdentifier = provider.registeredTypeIdentifiers.first(where: {
            guard let type = UTType($0) else { return false }
            return type.conforms(to: .item)
        }) ?? provider.registeredTypeIdentifiers.first else {
            throw ShareImportError.noReadableItems
        }

        return try await withCheckedThrowingContinuation { continuation in
            providerBox.provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw ShareImportError.noReadableItems }
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    let isDirectory = values?.isDirectory == true
                    let proposedName = providerBox.provider.suggestedName?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let originalName = (proposedName?.isEmpty == false ? proposedName : nil)
                        ?? url.lastPathComponent
                    let safeName = safeItemName(originalName, fallback: isDirectory ? "Folder" : "File")
                    let destination = uniqueDestination(
                        named: safeName,
                        isDirectory: isDirectory,
                        in: payload
                    )
                    let hasAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: Item(
                        name: destination.lastPathComponent,
                        isDirectory: isDirectory
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func write(_ request: Request, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        try data.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
    }

    private static func requestDirectoryURL(for id: String) -> URL {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )!
        return container
            .appendingPathComponent(inboxDirectoryName, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    private static func safeItemName(_ raw: String, fallback: String) -> String {
        let name = (raw as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "." || name == ".." ? fallback : name
    }

    private static func uniqueDestination(named name: String, isDirectory: Bool, in root: URL) -> URL {
        let initial = root.appendingPathComponent(name, isDirectory: isDirectory)
        guard !FileManager.default.fileExists(atPath: initial.path) else {
            let fileExtension = isDirectory ? "" : (name as NSString).pathExtension
            let baseName = fileExtension.isEmpty
                ? name
                : (name as NSString).deletingPathExtension
            var suffix = 2
            while true {
                let candidateName = fileExtension.isEmpty
                    ? "\(baseName) \(suffix)"
                    : "\(baseName) \(suffix).\(fileExtension)"
                let candidate = root.appendingPathComponent(candidateName, isDirectory: isDirectory)
                if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
                suffix += 1
            }
        }
        return initial
    }
}

private final class ItemProviderBox: @unchecked Sendable {
    let provider: NSItemProvider

    init(_ provider: NSItemProvider) {
        self.provider = provider
    }
}

private enum ShareImportError: LocalizedError {
    case appGroupUnavailable
    case noReadableItems
    case cannotOpenApp

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return TalkifyLocalized.string("share.cannot_access_shared")
        case .noReadableItems:
            return TalkifyLocalized.string("share.no_readable_files")
        case .cannotOpenApp:
            return TalkifyLocalized.string("share.materials_received_reminder")
        }
    }
}
