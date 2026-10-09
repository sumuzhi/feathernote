package com.smartminutes.smart_minutes_flutter

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * 导入音视频平台通道（`feathernote/media_import`）。
 *
 * 契约 SSOT：docs/IMPORT-PIPELINE-DESIGN.md §6.2 / §6.4。
 * - probeMedia：MediaExtractor 遍历 track 判断 MIME 前缀（audio/ / video/），KEY_DURATION 取最大值；
 * - extractAudioTrack：MediaExtractor 选音轨 + MediaMuxer(MPEG_4) 逐 sample 拷贝——
 *   **不解码、零转码**，产物为 AAC-in-MP4（.m4a）；
 * - cancelExtract：按 token（=meetingId）置取消标志，提取侧在每个 sample 前检查。
 *
 * 错误码：E_UNSUPPORTED_CONTAINER / E_NO_AUDIO_TRACK / E_CANCELLED / E_SRC_UNREADABLE /
 * E_EXTRACT_FAILED（用户文案在 message 中给出，Dart 侧透传）。
 *
 * 注意：容器白名单（mp4/mov/m4v）由 Dart 侧屏 14 预检先行拦截（§7 双保险），
 * 通道内对 setDataSource 失败一律报 E_SRC_UNREADABLE / E_UNSUPPORTED_CONTAINER。
 */
object MediaImportPlugin {
    private const val CHANNEL = "feathernote/media_import"

    /** logcat 诊断 tag（探测音轨判定链路的可观测入口）。 */
    private const val TAG = "MediaImport"

    /** token（=meetingId）→ 取消标志。 */
    private val cancelFlags: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** 单线程执行器：MediaExtractor/MediaMuxer 均为重 IO，避免阻塞主线程导致 ANR。 */
    private val executor = Executors.newSingleThreadExecutor()

    /** MethodChannel result 必须回到主线程。 */
    private val mainHandler = Handler(Looper.getMainLooper())

    /** 注册到 Flutter 引擎（MainActivity.configureFlutterEngine 调用一次）。 */
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probeMedia" -> probeMedia(call, result)
                    "extractAudioTrack" -> extractAudioTrack(call, result)
                    "cancelExtract" -> cancelExtract(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    // ---------------------------------------------------------------- probeMedia

    private fun probeMedia(call: MethodCall, result: MethodChannel.Result) {
        val path: String = call.argument<String>("path")
            ?: return respondError(result, "E_SRC_UNREADABLE", "参数缺少 path")
        executor.execute {
            // 前置校验：文件必须存在且有内容（file_picker cache 副本可能为空/半成品）。
            val file = File(path)
            if (!file.exists() || file.length() <= 0L) {
                respondError(
                    result, "E_SRC_UNREADABLE",
                    "文件读取失败，可能已被移动或删除",
                )
                return@execute
            }

            val extractor = MediaExtractor()
            try {
                val probe = scanTracks(extractor, path)

                var trackCount = probe.trackCount
                var trackMimes = probe.trackMimes
                var hasAudio = probe.hasAudio
                var isVideoContainer = probe.isVideoContainer
                var mimeType = probe.mimeType
                var durationMs = probe.durationMs
                var source = "extractor"

                // 兜底①：String 重载解不出任何轨（SAF/cache 路径下 Java File API 有时不全）
                // → 改用 FileDescriptor 重载再探一次。
                if (trackCount == 0) {
                    val retry = scanTracksViaFd(path)
                    if (retry != null && retry.trackCount > 0) {
                        trackCount = retry.trackCount
                        trackMimes = retry.trackMimes
                        hasAudio = retry.hasAudio
                        isVideoContainer = retry.isVideoContainer
                        if (mimeType.isEmpty()) mimeType = retry.mimeType
                        if (retry.durationMs > durationMs) durationMs = retry.durationMs
                        source = "extractor-fd"
                    }
                }

                // 兜底②：有轨但未识别到 audio/ → 用 MediaMetadataRetriever 复核。
                var retrieverOverride = false
                if (trackCount > 0 && !hasAudio) {
                    val claimed = retrieverHasAudio(path)
                    if (claimed == true) {
                        hasAudio = true
                        retrieverOverride = true
                        source = "retriever-override"
                    }
                }

                val diagnostics = buildString {
                    append("path=").append(path)
                    append(" exists=").append(file.exists())
                    append(" size=").append(file.length())
                    append(" trackCount=").append(trackCount)
                    append(" mimes=").append(trackMimes)
                    append(" durationMs=").append(durationMs)
                    append(" source=").append(source)
                    if (retrieverOverride) append(" retrieverOverride=true")
                }
                Log.d(TAG, diagnostics)

                respond(result, mapOf(
                    "durationMs" to durationMs,
                    "hasAudio" to hasAudio,
                    "isVideoContainer" to isVideoContainer,
                    "mimeType" to mimeType,
                    "trackCount" to trackCount,
                    "trackMimes" to trackMimes,
                ))
            } catch (e: Exception) {
                Log.d(TAG, "probeMedia failed path=$path err=${e.message}")
                respondError(
                    result, "E_SRC_UNREADABLE",
                    "文件读取失败，可能已被移动或删除（${e.message ?: "未知原因"}）",
                )
            } finally {
                try {
                    extractor.release()
                } catch (_: Exception) {
                }
            }
        }
    }

    /** 单次 track 扫描结果。 */
    private data class TrackScan(
        val trackCount: Int,
        val trackMimes: List<String>,
        val hasAudio: Boolean,
        val isVideoContainer: Boolean,
        val durationMs: Long,
        val mimeType: String,
    )

    /** 用 MediaExtractor(String) 扫描轨道。 */
    private fun scanTracks(extractor: MediaExtractor, path: String): TrackScan {
        extractor.setDataSource(path)
        return collectTracks(extractor)
    }

    /** 用 MediaExtractor(FileDescriptor) 扫描轨道（失败返回 null）。 */
    private fun scanTracksViaFd(path: String): TrackScan? {
        var pfd: ParcelFileDescriptor? = null
        val extractor = MediaExtractor()
        return try {
            pfd = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
            extractor.setDataSource(pfd.fileDescriptor)
            collectTracks(extractor)
        } catch (e: Exception) {
            Log.d(TAG, "scanTracksViaFd failed path=$path err=${e.message}")
            null
        } finally {
            try {
                extractor.release()
            } catch (_: Exception) {
            }
            try {
                pfd?.close()
            } catch (_: Exception) {
            }
        }
    }

    /** 遍历已 setDataSource 的 extractor 收集轨道信息。 */
    private fun collectTracks(extractor: MediaExtractor): TrackScan {
        var durationMs = 0L
        var hasAudio = false
        var isVideoContainer = false
        var mimeType = ""
        val mimes = mutableListOf<String>()
        for (i in 0 until extractor.trackCount) {
            val format: MediaFormat = extractor.getTrackFormat(i)
            val trackMime: String = format.getString(MediaFormat.KEY_MIME) ?: ""
            mimes.add("$i:$trackMime")
            val trackDurationUs =
                if (format.containsKey(MediaFormat.KEY_DURATION)) {
                    format.getLong(MediaFormat.KEY_DURATION)
                } else {
                    0L
                }
            val trackDurationMs = trackDurationUs / 1000
            if (trackDurationMs > durationMs) durationMs = trackDurationMs
            if (trackMime.startsWith("audio/")) {
                hasAudio = true
                if (mimeType.isEmpty()) mimeType = trackMime
            } else if (trackMime.startsWith("video/")) {
                isVideoContainer = true
                if (mimeType.isEmpty()) mimeType = trackMime
            }
        }
        return TrackScan(
            trackCount = extractor.trackCount,
            trackMimes = mimes,
            hasAudio = hasAudio,
            isVideoContainer = isVideoContainer,
            durationMs = durationMs,
            mimeType = mimeType,
        )
    }

    /** MediaMetadataRetriever 复核是否有音轨（true/false；解不出返回 null）。 */
    private fun retrieverHasAudio(path: String): Boolean? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val flag = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)
            when (flag?.lowercase()) {
                "yes" -> true
                "no" -> false
                else -> null
            }
        } catch (e: Exception) {
            Log.d(TAG, "retrieverHasAudio failed path=$path err=${e.message}")
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }
    }

    // ------------------------------------------------------------ extractAudioTrack

    private fun extractAudioTrack(call: MethodCall, result: MethodChannel.Result) {
        val token: String = call.argument<String>("token")
            ?: return respondError(result, "E_SRC_UNREADABLE", "参数缺少 token")
        val srcPath: String = call.argument<String>("srcPath")
            ?: return respondError(result, "E_SRC_UNREADABLE", "参数缺少 srcPath")
        val destPath: String = call.argument<String>("destPath")
            ?: return respondError(result, "E_SRC_UNREADABLE", "参数缺少 destPath")
        executor.execute {
            val destFile = File(destPath)
            val extractor = MediaExtractor()
            var muxer: MediaMuxer? = null
            try {
                // 清理上一次「提取结束后才到达」的取消残留，保证重试可从头跑。
                cancelFlags.remove(token)
                checkCancelled(token)
                extractor.setDataSource(srcPath)

                // 1) 找第一个音频轨（hasAudio=false → E_NO_AUDIO_TRACK）。
                var audioIndex = -1
                var audioFormat: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val format: MediaFormat = extractor.getTrackFormat(i)
                    val mime: String = format.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) {
                        audioIndex = i
                        audioFormat = format
                        break
                    }
                }
                val format: MediaFormat = audioFormat
                    ?: throw MediaImportException("E_NO_AUDIO_TRACK", "该视频没有可用的音频轨道")
                val durationMs: Long =
                    if (format.containsKey(MediaFormat.KEY_DURATION)) {
                        format.getLong(MediaFormat.KEY_DURATION) / 1000
                    } else {
                        0L
                    }

                // 2) MediaMuxer 逐 sample 拷贝（零解码零转码）。
                muxer = MediaMuxer(destPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                val trackIndex: Int = muxer.addTrack(format)
                muxer.start()
                extractor.selectTrack(audioIndex)

                val maxInputSize = if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE)
                } else {
                    0
                }
                val buffer = ByteBuffer.allocateDirect(maxOf(maxInputSize, 256 * 1024))
                val info = MediaCodec.BufferInfo()
                var bytesWritten = 0L
                while (true) {
                    // 每个 sample 前查取消标志（§6.2）。
                    checkCancelled(token)
                    val sampleSize: Int = extractor.readSampleData(buffer, 0)
                    if (sampleSize < 0) break
                    info.offset = 0
                    info.size = sampleSize
                    info.presentationTimeUs = extractor.sampleTime
                    info.flags = extractor.sampleFlags
                    muxer.writeSampleData(trackIndex, buffer, info)
                    bytesWritten += sampleSize
                    extractor.advance()
                }
                muxer.stop()
                respond(result, mapOf(
                    "path" to destPath,
                    "durationMs" to durationMs,
                    "bytesWritten" to bytesWritten,
                ))
            } catch (e: MediaImportException) {
                destFile.delete()
                respondError(result, e.code, e.message ?: "音轨分离失败")
            } catch (e: Exception) {
                destFile.delete()
                respondError(
                    result, "E_EXTRACT_FAILED",
                    "音轨分离失败，请重试或转成 mp4 后重试（${e.message ?: "未知原因"}）",
                )
            } finally {
                cancelFlags.remove(token)
                try {
                    extractor.release()
                } catch (_: Exception) {
                }
                try {
                    muxer?.release()
                } catch (_: Exception) {
                }
            }
        }
    }

    // ---------------------------------------------------------------- cancelExtract

    private fun cancelExtract(call: MethodCall, result: MethodChannel.Result) {
        val token: String = call.argument<String>("token") ?: ""
        // 幂等：置标志即可；未在进行的 token 置位后由提取侧 finally 清理，无害。
        cancelFlags.add(token)
        respond(result, mapOf("cancelled" to true))
    }

    // -------------------------------------------------------------------- 工具

    private fun checkCancelled(token: String) {
        if (cancelFlags.contains(token)) {
            throw MediaImportException("E_CANCELLED", "用户取消")
        }
    }

    private fun respond(result: MethodChannel.Result, payload: Map<String, Any?>) {
        mainHandler.post { result.success(payload) }
    }

    private fun respondError(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    /** 带平台错误码的业务异常。 */
    private class MediaImportException(val code: String, message: String) : Exception(message)
}
