import Foundation
import AgentKit
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class TalkifyUserAssetPicker {
    private let fileStore: ManagedUserAssetFileStore
    private let normalizer: UserImageNormalizer
    private let accountScope: @Sendable () -> String
    #if os(iOS)
    private var coordinator: IOSPickerCoordinator?
    #endif

    init(
        fileStore: ManagedUserAssetFileStore,
        normalizer: UserImageNormalizer,
        accountScope: @escaping @Sendable () -> String
    ) {
        self.fileStore = fileStore
        self.normalizer = normalizer
        self.accountScope = accountScope
    }

    func pick() async throws -> [DraftAttachmentReference] {
        #if os(iOS)
        let attachments = try await pickOnIOS()
        #elseif os(macOS)
        let attachments = try pickOnMacOS()
        #else
        let attachments: [DraftAttachmentReference] = []
        #endif
        return try await preflightCombinedSize(attachments)
    }

    private func preflightCombinedSize(
        _ attachments: [DraftAttachmentReference]
    ) async throws -> [DraftAttachmentReference] {
        let normalizer = normalizer
        let images = try await Task.detached(priority: .userInitiated) {
            try attachments.map { attachment in
                guard let url = URL(string: attachment.resourceURI) else {
                    throw ManagedUserAssetFileError.invalidResource
                }
                return try normalizer.normalize(
                    sourceURL: url,
                    attachmentID: attachment.id,
                    preferredFilename: attachment.displayName
                )
            }
        }.value
        try UserImageNormalizer.validateCombinedSize(images)
        return attachments
    }

    #if os(iOS)
    private func pickOnIOS() async throws -> [DraftAttachmentReference] {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 4
        configuration.selection = .ordered

        let picker = PHPickerViewController(configuration: configuration)
        let coordinator = IOSPickerCoordinator(
            fileStore: fileStore,
            accountScope: accountScope()
        )
        self.coordinator = coordinator
        picker.delegate = coordinator

        guard let presenter = Self.presentingViewController() else {
            self.coordinator = nil
            throw ManagedUserAssetFileError.unavailable
        }
        presenter.present(picker, animated: true)
        defer { self.coordinator = nil }
        return try await coordinator.result()
    }

    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var controller = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
    #endif

    #if os(macOS)
    private func pickOnMacOS() throws -> [DraftAttachmentReference] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image]
        panel.message = String(localized: "user-assets.picker.message")
        guard panel.runModal() == .OK else { return [] }

        let scope = accountScope()
        return try panel.urls.prefix(4).map { url in
            let id = UUID().uuidString.lowercased()
            let managed = try fileStore.importFile(from: url, attachmentID: id, accountScope: scope)
            return DraftAttachmentReference(
                id: id,
                displayName: UserImageNormalizer.safeFilename(url.lastPathComponent, mimeType: nil),
                resourceURI: managed.absoluteString
            )
        }
    }
    #endif
}

#if os(iOS)
@MainActor
private final class IOSPickerCoordinator: NSObject, PHPickerViewControllerDelegate {
    private let fileStore: ManagedUserAssetFileStore
    private let accountScope: String
    private var continuation: CheckedContinuation<[PHPickerResult], Never>?
    private var bufferedResults: [PHPickerResult]?

    init(fileStore: ManagedUserAssetFileStore, accountScope: String) {
        self.fileStore = fileStore
        self.accountScope = accountScope
    }

    func result() async throws -> [DraftAttachmentReference] {
        let results: [PHPickerResult] = await withCheckedContinuation { continuation in
            if let bufferedResults {
                continuation.resume(returning: bufferedResults)
                self.bufferedResults = nil
            } else {
                self.continuation = continuation
            }
        }
        var attachments: [DraftAttachmentReference] = []
        for result in results.prefix(4) {
            let id = UUID().uuidString.lowercased()
            let name = result.itemProvider.suggestedName ?? "image"
            let managedURL = try await importProvider(result.itemProvider, attachmentID: id)
            attachments.append(DraftAttachmentReference(
                id: id,
                displayName: UserImageNormalizer.safeFilename(name, mimeType: nil),
                resourceURI: managedURL.absoluteString
            ))
        }
        return attachments
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: results)
        } else {
            bufferedResults = results
        }
    }

    private func importProvider(_ provider: NSItemProvider, attachmentID: String) async throws -> URL {
        let type = provider.registeredTypeIdentifiers.first(where: {
            UTType($0)?.conforms(to: .image) == true
        }) ?? UTType.image.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { [fileStore, accountScope] url, error in
                guard error == nil, let url else {
                    continuation.resume(throwing: ManagedUserAssetFileError.unavailable)
                    return
                }
                do {
                    let copied = try fileStore.importFile(
                        from: url,
                        attachmentID: attachmentID,
                        accountScope: accountScope
                    )
                    continuation.resume(returning: copied)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
