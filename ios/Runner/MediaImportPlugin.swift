import AVFoundation
import Foundation
import Flutter
import UniformTypeIdentifiers

/// 导入音视频平台通道（`feathernote/media_import`）。
///
/// 契约 SSOT：docs/IMPORT-PIPELINE-DESIGN.md §6.3 / §6.4。
/// - probeMedia：AVURLAsset.load(.duration / .tracks) 遍历轨判断 mediaType（iOS 15+ 异步 API，
///   项目 deployment target = 15.0）；
/// - extractAudioTrack：AVAssetExportSession(presetAppleM4A) 导出 m4a——**零解码零转码**；
///   对视频 asset 直接 M4A 失败时的兜底（§6.3）：先 passthrough 转封装为 .mov，
///   再对 .mov 跑 presetAppleM4A（两段都零转码）；
/// - cancelExtract：按 token（=meetingId）置取消标志，导出轮询任务看到后 cancelExport。
///
/// 错误码：E_UNSUPPORTED_CONTAINER / E_NO_AUDIO_TRACK / E_CANCELLED / E_SRC_UNREADABLE /
/// E_EXTRACT_FAILED（用户文案在 message 中给出，Dart 侧透传）。
@objc public final class MediaImportPlugin: NSObject {
  private static let channelName = "feathernote/media_import"

  /// token（=meetingId）→ 取消标志。加锁保护（导出轮询在后台 Task 检查）。
  private static var cancelFlags: Set<String> = []
  private static let flagsLock = NSLock()

  /// 注册到 Flutter 引擎（AppDelegate.didInitializeImplicitFlutterEngine 调用一次）。
  public static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "probeMedia":
        handleProbe(arguments: call.arguments, result: result)
      case "extractAudioTrack":
        handleExtract(arguments: call.arguments, result: result)
      case "cancelExtract":
        handleCancel(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // ------------------------------------------------------------------ probeMedia

  private static func handleProbe(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let path = args["path"] as? String else {
      respondError(result, "E_SRC_UNREADABLE", "参数缺少 path")
      return
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    Task {
      do {
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        var hasAudio = false
        var isVideoContainer = false
        var mimeType = ""
        for track in tracks {
          if track.mediaType == .audio {
            hasAudio = true
          } else if track.mediaType == .video {
            isVideoContainer = true
          }
        }
        // 由扩展名尽力猜测 MIME（探测结果的主要判断字段是 hasAudio/isVideoContainer）。
        let mimeType = guessMime(path: path)
        let durationMs = Int(CMTimeGetSeconds(duration) * 1000)
        respond(result, [
          "durationMs": durationMs,
          "hasAudio": hasAudio,
          "isVideoContainer": isVideoContainer,
          "mimeType": mimeType,
        ])
      } catch {
        respondError(
          result, "E_SRC_UNREADABLE",
          "文件读取失败，可能已被移动或删除（\(error.localizedDescription)）")
      }
    }
  }

  // ------------------------------------------------------------ extractAudioTrack

  private static func handleExtract(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let token = args["token"] as? String,
      let srcPath = args["srcPath"] as? String,
      let destPath = args["destPath"] as? String
    else {
      respondError(result, "E_SRC_UNREADABLE", "参数缺少 token/srcPath/destPath")
      return
    }
    Task {
      let destURL = URL(fileURLWithPath: destPath)
      do {
        // 清理上一次「提取结束后才到达」的取消残留，保证重试可从头跑。
        setCancelled(token, false)
        checkCancelled(token)
        try? FileManager.default.removeItem(at: destURL)

        let srcAsset = AVURLAsset(url: URL(fileURLWithPath: srcPath))
        let tracks = try await srcAsset.load(.tracks)
        let hasAudio = tracks.contains { $0.mediaType == .audio }
        if !hasAudio {
          throw ImportError(code: "E_NO_AUDIO_TRACK", message: "该视频没有可用的音频轨道")
        }

        let srcDuration = try await srcAsset.load(.duration)
        let durationMs = Int(CMTimeGetSeconds(srcDuration) * 1000)

        // 第一次尝试：直接 presetAppleM4A（音轨 asset 一次到位）。
        do {
          try await exportM4A(asset: srcAsset, dest: destURL, token: token)
          finishExtract(result, dest: destPath, durationMs: durationMs)
        } catch {
          if isCancellation(error) { throw error }
          // 兜底（§6.3 / R1）：passthrough 只做容器转封装（.mov，零转码），
          // 再对 .mov 跑 presetAppleM4A。部分系统版本 M4A 直接作用于视频 asset 会失败。
          let movURL = destURL.deletingPathExtension().appendingPathExtension("tmp.mov")
          defer { try? FileManager.default.removeItem(at: movURL) }
          do {
            try await runExport(
              asset: srcAsset, preset: AVAssetExportPresetPassthrough,
              fileType: .mov, dest: movURL, token: token)
            let passthroughAsset = AVURLAsset(url: movURL)
            try await exportM4A(asset: passthroughAsset, dest: destURL, token: token)
            finishExtract(result, dest: destPath, durationMs: durationMs)
          } catch {
            try? FileManager.default.removeItem(at: destURL)
            throw mapExportError(error)
          }
        }
      } catch {
        setCancelled(token, false)
        let importError = mapExportError(error)
        try? FileManager.default.removeItem(at: destURL)
        respondError(result, importError.code, importError.message)
      }
    }
  }

  /// presetAppleM4A 导出（音频源 → .m4a）。
  private static func exportM4A(asset: AVAsset, dest: URL, token: String) async throws {
    try await runExport(
      asset: asset, preset: AVAssetExportPresetAppleM4A,
      fileType: .m4a, dest: dest, token: token)
  }

  /// 通用导出：启动取消轮询任务（200ms 查一次标志位，置位则 cancelExport）。
  private static func runExport(
    asset: AVAsset, preset: String, fileType: AVFileType, dest: URL, token: String
  ) async throws {
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw ImportError(code: "E_EXTRACT_FAILED", message: "无法创建导出会话")
    }
    session.outputURL = dest
    session.outputFileType = fileType
    let pollTask = Task {
      while !Task.isCancelled {
        if isCancelled(token) {
          session.cancelExport()
          break
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
      }
    }
    defer { pollTask.cancel() }
    try? FileManager.default.removeItem(at: dest)
    await session.export()
    switch session.status {
    case .completed:
      return
    case .cancelled:
      throw ImportError(code: "E_CANCELLED", message: "用户取消")
    default:
      throw ImportError(
        code: classifyExportError(session.error),
        message: session.error?.localizedDescription ?? "音轨分离失败，请重试或转成 mp4 后重试")
    }
  }

  private static func finishExtract(
    _ result: @escaping FlutterResult, dest: String, durationMs: Int
  ) {
    var bytesWritten = 0
    if let attrs = try? FileManager.default.attributesOfItem(atPath: dest),
      let size = attrs[.size] as? Int {
      bytesWritten = size
    }
    respond(result, [
      "path": dest,
      "durationMs": durationMs,
      "bytesWritten": bytesWritten,
    ])
  }

  // ------------------------------------------------------------------ cancelExtract

  private static func handleCancel(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let token = args["token"] as? String else {
      respond(result, ["cancelled": false])
      return
    }
    setCancelled(token, true)
    respond(result, ["cancelled": true])
  }

  // ------------------------------------------------------------------------ 工具

  private struct ImportError: Error {
    let code: String
    let message: String
  }

  private static func isCancelled(_ error: Error) -> Bool {
    guard let importError = error as? ImportError else { return false }
    return importError.code == "E_CANCELLED"
  }

  /// AVExport 失败 → 平台错误码（§6.4）：兼容性/容器问题报 E_UNSUPPORTED_CONTAINER，
  /// 其余报 E_EXTRACT_FAILED；取消透传。
  private static func mapExportError(_ error: Error) -> ImportError {
    if let importError = error as? ImportError { return importError }
    let code = classifyExportError(error)
    let message = (error as NSError).localizedDescription
    return ImportError(
      code: code,
      message: code == "E_UNSUPPORTED_CONTAINER"
        ? "暂不支持该视频格式，请转成 mp4 后重试" : "音轨分离失败，请重试或转成 mp4 后重试（\(message)）")
  }

  private static func classifyExportError(_ error: Error?) -> String {
    guard let nsError = error as NSError?, nsError.domain == AVError.errorDomain else {
      return "E_EXTRACT_FAILED"
    }
    switch AVError.Code(rawValue: nsError.code) {
    case .incompatibleAsset, .contentIsUnavailable, .noLongerPlayable, .noTrackToPerformMediaSelection:
      return "E_UNSUPPORTED_CONTAINER"
    default:
      return "E_EXTRACT_FAILED"
    }
  }

  /// 由扩展名尽力猜测 MIME 类型（猜不出为空串）。
  private static func guessMime(path: String) -> String {
    let ext = (path as NSString).pathExtension
    return UTType(filenameExtension: ext)?.preferredMIMEType ?? ""
  }

  // 取消标志（锁保护）。

  private static func isCancelled(_ token: String) -> Bool {
    flagsLock.lock()
    defer { flagsLock.unlock() }
    return cancelFlags.contains(token)
  }

  private static func setCancelled(_ token: String, _ cancelled: Bool) {
    flagsLock.lock()
    defer { flagsLock.unlock() }
    if cancelled {
      cancelFlags.insert(token)
    } else {
      cancelFlags.remove(token)
    }
  }

  private static func checkCancelled(_ token: String) throws {
    if isCancelled(token) {
      throw ImportError(code: "E_CANCELLED", message: "用户取消")
    }
  }

  private static func respond(_ result: @escaping FlutterResult, _ payload: [String: Any]) {
    DispatchQueue.main.async { result(payload) }
  }

  private static func respondError(
    _ result: @escaping FlutterResult, _ code: String, _ message: String
  ) {
    DispatchQueue.main.async { result(FlutterError(code: code, message: message, details: nil)) }
  }
}
