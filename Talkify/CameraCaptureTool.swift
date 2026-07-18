//
//  CameraCaptureTool.swift
//  CodeAgent
//
//  P1 Demo: 摄像头拍照工具（iOS + macOS 双平台）。
//  使用 AVFoundation AVCaptureSession 程序化拍照，无需 UI 呈现。
//  首次使用会触发系统摄像头权限弹窗。
//

import Foundation
import AVFoundation
import Photos
import AgentKit
#if os(iOS)
import UIKit
#endif

/// 摄像头拍照工具 — 使用 AVFoundation 原生 API。
/// iOS 使用后置/前置摄像头，macOS 使用内置 FaceTime 摄像头。
/// 程序化捕获，无需 UI — 适合 Agent 在工作流中自动调用。
struct CameraCaptureTool: ClientTool {
    let name = "capture_photo"
    let description = """
使用设备摄像头拍摄一张照片并保存到临时 JPEG 文件。返回照片文件的完整路径、文件大小和分辨率。
适用场景：用户要求拍照、视觉识别、场景记录、人脸检测等。
参数：
  - camera (可选): "front" 使用前置摄像头，"back" 使用后置摄像头，默认 "back"
  - save_path (可选): 自定义保存路径，默认保存到临时目录
注意：首次使用会弹出系统摄像头权限对话框，用户需授权后重试。
照片拍摄后会自动保存到系统相册，方便用户查看。
"""

    var inputSchema: JSONValue? {
        .object([
            "type": .string("object"),
            "properties": .object([
                "camera": .object([
                    "type": .string("string"),
                    "description": .string("摄像头选择：\"front\"（前置/FaceTime）/ \"back\"（后置），默认 \"back\"")
                ]),
                "save_path": .object([
                    "type": .string("string"),
                    "description": .string("照片保存路径（可选，默认保存到临时目录）")
                ])
            ]),
            "required": .array([])
        ])
    }

    func execute(args: JSONValue?) async throws -> String {
        // 解析参数
        var useFrontCamera = false
        var outputPath: String

        if case .object(let dict) = args {
            if case .string(let camera) = dict["camera"], camera == "front" {
                useFrontCamera = true
            }
            if case .string(let customPath) = dict["save_path"] {
                outputPath = customPath
            }
        }

        // 默认输出路径
        let tmpDir = FileManager.default.temporaryDirectory
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = "photo_\(formatter.string(from: Date())).jpg"
        outputPath = tmpDir.appendingPathComponent(filename).path

        let startTime = Date()

        // 1. 检查/请求摄像头权限
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw CameraError.permissionDenied
            }
        case .denied:
            throw CameraError.permissionDenied
        case .restricted:
            throw CameraError.restricted
        @unknown default:
            throw CameraError.permissionDenied
        }

        // 2. 创建 AVCaptureSession
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        // 3. 查找摄像头
        let position: AVCaptureDevice.Position = useFrontCamera ? .front : .back
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        guard let camera = discoverySession.devices.first else {
            throw CameraError.noCameraFound(position: useFrontCamera ? "前置" : "后置")
        }

        // 4. 添加输入
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }
        session.addInput(input)

        // 5. 添加照片输出
        let photoOutput = AVCapturePhotoOutput()
        guard session.canAddOutput(photoOutput) else {
            throw CameraError.cannotAddOutput
        }
        session.addOutput(photoOutput)

        // 6. 启动会话
        await MainActor.run {
            session.startRunning()
        }

        // 等待摄像头预热
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

        // 7. 拍照
        let settings = AVCapturePhotoSettings()
        let handler = PhotoCaptureHandler()
        let photoData = try await handler.capture(using: photoOutput, settings: settings)

        // 8. 停止会话
        await MainActor.run {
            session.stopRunning()
        }

        // 9. 写入临时文件
        let url = URL(fileURLWithPath: outputPath)
        try photoData.write(to: url, options: .atomic)

        // 10. 保存到系统相册 (iOS only)
        var savedToGallery = false
#if os(iOS)
        let albumStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch albumStatus {
        case .authorized, .limited:
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: UIImage(data: photoData)!)
                }
                savedToGallery = true
            } catch {
                // 相册保存失败不抛异常，拍照本身已成功
            }
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if granted == .authorized || granted == .limited {
                do {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: UIImage(data: photoData)!)
                    }
                    savedToGallery = true
                } catch {
                    // 同上
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
#endif

        let elapsed = Date().timeIntervalSince(startTime)

        let fileSize: String
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
           let size = attrs[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            fileSize = "未知"
        }

        // 从图片数据解析分辨率
        let resolution: String
        if let source = CGImageSourceCreateWithData(photoData as CFData, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            resolution = "\(width)x\(height)"
        } else {
            resolution = "未知"
        }

        return """
        photo_captured: true
        file_path: \(outputPath)
        file_size: \(fileSize)
        resolution: \(resolution)
        camera: \(useFrontCamera ? "front" : "back")
        saved_to_gallery: \(savedToGallery)
        elapsed_seconds: \(String(format: "%.1f", elapsed))
        """
    }
}

// MARK: - PhotoCaptureHandler

/// 将 AVCapturePhotoCaptureDelegate 回调桥接为 async/await。
private final class PhotoCaptureHandler: NSObject, AVCapturePhotoCaptureDelegate {
    private var continuation: CheckedContinuation<Data, Error>?

    func capture(using output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation() {
            continuation?.resume(returning: data)
        } else {
            continuation?.resume(throwing: CameraError.captureFailed)
        }
        continuation = nil
    }
}

// MARK: - CameraError

enum CameraError: LocalizedError {
    case permissionDenied
    case restricted
    case noCameraFound(position: String)
    case cannotAddInput
    case cannotAddOutput
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "摄像头权限被拒绝。请打开 系统设置 → 隐私与安全性 → 相机，允许本应用访问摄像头后重试。"
        case .restricted:
            return "摄像头访问受到限制（家长控制或企业策略）。"
        case .noCameraFound(let position):
            return "未找到\(position)摄像头。请确认设备已连接摄像头。"
        case .cannotAddInput:
            return "无法将摄像头输入添加到捕获会话。"
        case .cannotAddOutput:
            return "无法将照片输出添加到捕获会话。"
        case .captureFailed:
            return "拍照失败：未能获取照片数据。"
        }
    }
}
