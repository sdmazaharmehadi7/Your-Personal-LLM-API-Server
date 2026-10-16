import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/local_model.dart';

class UrlValidationResult {
  final bool isValid;
  final String? resolvedUrl;
  final String? suggestedFilename;
  final String? error;

  const UrlValidationResult({
    required this.isValid,
    this.resolvedUrl,
    this.suggestedFilename,
    this.error,
  });
}

class ModelDownloadProgress {
  final String modelId;
  final ModelDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final double speedBytesPerSec;
  final String? savedFilePath;
  final String? error;

  const ModelDownloadProgress({
    required this.modelId,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.speedBytesPerSec,
    this.savedFilePath,
    this.error,
  });

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '0 KB/s';
    if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
  }

  String get formattedDownloadedSize {
    final downloadedMb = downloadedBytes / (1024 * 1024);
    if (totalBytes > 0) {
      final totalMb = totalBytes / (1024 * 1024);
      if (totalMb >= 1024) {
        return '${(downloadedMb / 1024).toStringAsFixed(2)} / ${(totalMb / 1024).toStringAsFixed(2)} GB';
      }
      return '${downloadedMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB';
    }
    return '${downloadedMb.toStringAsFixed(1)} MB';
  }
}

abstract class IModelDownloadService {
  Stream<ModelDownloadProgress> get progressStream;
  Future<void> startDownload(LocalModel model, String targetDirectory);
  Future<void> pauseDownload(String modelId);
  Future<void> resumeDownload(LocalModel model, String targetDirectory);
  Future<void> cancelDownload(String modelId);
  Future<void> deleteModelFile(String filePath);
  Future<void> validateGgufHeader(File file);
  Future<void> copyFileWithProgress(
    String sourcePath,
    String targetPath, {
    void Function(double progress)? onProgress,
  });
  bool isDownloading(String modelId);
  void dispose();
}

class _ActiveDownload {
  final String modelId;
  final String finalPath;
  final String partPath;
  http.Client? client;
  StreamSubscription<List<int>>? subscription;
  IOSink? sink;
  Completer<void>? completer;
  bool isPaused = false;
  bool isCancelled = false;

  _ActiveDownload({
    required this.modelId,
    required this.finalPath,
    required this.partPath,
  });
}

class ModelDownloadService implements IModelDownloadService {
  final http.Client Function()? clientFactory;
  final StreamController<ModelDownloadProgress> _progressController =
      StreamController<ModelDownloadProgress>.broadcast();
  final Map<String, _ActiveDownload> _activeDownloads = {};

  ModelDownloadService({this.clientFactory});

  @override
  Stream<ModelDownloadProgress> get progressStream =>
      _progressController.stream;

  @override
  bool isDownloading(String modelId) {
    final task = _activeDownloads[modelId];
    return task != null && !task.isPaused && !task.isCancelled;
  }

  int get _activeCount => _activeDownloads.values
      .where((d) => !d.isPaused && !d.isCancelled)
      .length;

  Future<void> _updateWakelock() async {
    try {
      if (_activeCount > 0) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Safe guard against platforms or test environments without wakelock support
    }
  }

  static UrlValidationResult validateAndResolveUrl(String inputUrl) {
    final trimmed = inputUrl.trim();
    if (trimmed.isEmpty) {
      return const UrlValidationResult(
        isValid: false,
        error: 'Please enter a download URL.',
      );
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return const UrlValidationResult(
        isValid: false,
        error: 'Invalid URL format. URL must begin with https:// or http://.',
      );
    }

    // Auto-convert Hugging Face /blob/ URLs to direct /resolve/ URLs
    var resolved = trimmed;
    if (uri.host.contains('huggingface.co') && uri.path.contains('/blob/')) {
      resolved = resolved.replaceAll('/blob/', '/resolve/');
    }

    final resolvedUri = Uri.parse(resolved);
    final segments = resolvedUri.pathSegments
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.isEmpty) {
      return const UrlValidationResult(
        isValid: false,
        error: 'URL has no target filename.',
      );
    }

    final rawFilename = segments.last;

    // Check if user linked to a general Hugging Face repository page instead of a file
    if (!rawFilename.toLowerCase().endsWith('.gguf')) {
      if (uri.host.contains('huggingface.co')) {
        return const UrlValidationResult(
          isValid: false,
          error:
              'This appears to be a repository or web page, not a direct model file. '
              'Please open the "Files" tab on Hugging Face, select the desired .gguf file, and copy its direct download link.',
        );
      }
      return const UrlValidationResult(
        isValid: false,
        error: 'Target URL does not appear to end with a .gguf model file extension.',
      );
    }

    // Sanitize filename to prevent path traversal
    final sanitizedFilename = rawFilename
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll('..', '_');

    return UrlValidationResult(
      isValid: true,
      resolvedUrl: resolved,
      suggestedFilename: sanitizedFilename,
    );
  }

  @override
  Future<void> startDownload(LocalModel model, String targetDirectory) async {
    await _executeDownload(model, targetDirectory, resume: false);
  }

  @override
  Future<void> resumeDownload(LocalModel model, String targetDirectory) async {
    await _executeDownload(model, targetDirectory, resume: true);
  }

  Future<void> _executeDownload(
    LocalModel model,
    String targetDirectory, {
    required bool resume,
  }) async {
    if (model.downloadUrl == null || model.downloadUrl!.isEmpty) {
      _emitProgress(
        modelId: model.id,
        status: ModelDownloadStatus.error,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0.0,
        speedBytesPerSec: 0.0,
        error: 'No download URL specified for this model.',
      );
      return;
    }

    if (isDownloading(model.id)) return;

    final targetDir = Directory(targetDirectory);
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final finalPath = '${targetDir.path}/${model.filename}';
    final partPath = '$finalPath.part';
    final partFile = File(partPath);

    int existingBytes = 0;
    if (resume && await partFile.exists()) {
      existingBytes = await partFile.length();
    } else if (!resume && await partFile.exists()) {
      await partFile.delete();
    }

    final active = _ActiveDownload(
      modelId: model.id,
      finalPath: finalPath,
      partPath: partPath,
    );
    _activeDownloads[model.id] = active;
    await _updateWakelock();

    final client = clientFactory != null ? clientFactory!() : http.Client();
    active.client = client;

    try {
      final request = http.Request('GET', Uri.parse(model.downloadUrl!));
      request.followRedirects = true;
      request.maxRedirects = 10;
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);

      if (active.isCancelled || active.isPaused) {
        client.close();
        return;
      }

      final isPartial = response.statusCode == 206;
      final isSuccess = response.statusCode == 200 || isPartial;

      if (!isSuccess) {
        throw HttpException(
          'Download server responded with HTTP ${response.statusCode}: ${response.reasonPhrase ?? ''}',
          uri: Uri.parse(model.downloadUrl!),
        );
      }

      final contentLength = response.contentLength ?? 0;
      final totalBytes = isPartial
          ? (existingBytes + contentLength)
          : contentLength;

      final openMode = (resume && isPartial && existingBytes > 0)
          ? FileMode.append
          : FileMode.write;

      int currentDownloaded = (resume && isPartial) ? existingBytes : 0;
      final sink = partFile.openWrite(mode: openMode);
      active.sink = sink;

      _emitProgress(
        modelId: model.id,
        status: ModelDownloadStatus.downloading,
        downloadedBytes: currentDownloaded,
        totalBytes: totalBytes,
        progress: totalBytes > 0 ? currentDownloaded / totalBytes : 0.0,
        speedBytesPerSec: 0.0,
      );

      var lastTime = DateTime.now();
      var lastBytes = currentDownloaded;
      double currentSpeed = 0.0;

      final completer = Completer<void>();
      active.completer = completer;

      active.subscription = response.stream.listen(
        (chunk) {
          if (active.isCancelled || active.isPaused) return;

          sink.add(chunk);
          currentDownloaded += chunk.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 400) {
            final bytesSinceLast = currentDownloaded - lastBytes;
            currentSpeed = (bytesSinceLast / (elapsedMs / 1000.0));
            lastTime = now;
            lastBytes = currentDownloaded;

            _emitProgress(
              modelId: model.id,
              status: ModelDownloadStatus.downloading,
              downloadedBytes: currentDownloaded,
              totalBytes: totalBytes,
              progress: totalBytes > 0
                  ? (currentDownloaded / totalBytes).clamp(0.0, 1.0)
                  : 0.0,
              speedBytesPerSec: currentSpeed,
            );
          }
        },
        onError: (Object err) {
          if (!completer.isCompleted) completer.completeError(err);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      await sink.flush();
      await sink.close();
      active.sink = null;

      if (active.isPaused) {
        _emitProgress(
          modelId: model.id,
          status: ModelDownloadStatus.paused,
          downloadedBytes: currentDownloaded,
          totalBytes: totalBytes,
          progress: totalBytes > 0 ? (currentDownloaded / totalBytes) : 0.0,
          speedBytesPerSec: 0.0,
        );
        return;
      }

      if (active.isCancelled) {
        if (await partFile.exists()) {
          await partFile.delete();
        }
        return;
      }

      // Verify file integrity (GGUF magic header)
      await validateGgufHeader(partFile);

      // Rename from .part to final .gguf
      final finalFile = File(finalPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await partFile.rename(finalPath);

      _emitProgress(
        modelId: model.id,
        status: ModelDownloadStatus.downloaded,
        downloadedBytes: currentDownloaded,
        totalBytes: currentDownloaded,
        progress: 1.0,
        speedBytesPerSec: 0.0,
        savedFilePath: finalPath,
      );
    } catch (e) {
      try {
        await active.sink?.flush();
        await active.sink?.close();
      } catch (_) {}
      active.sink = null;

      if (!active.isCancelled && !active.isPaused) {
        _emitProgress(
          modelId: model.id,
          status: ModelDownloadStatus.error,
          downloadedBytes: existingBytes,
          totalBytes: 0,
          progress: 0.0,
          speedBytesPerSec: 0.0,
          error: _categorizeError(e),
        );
      }
    } finally {
      client.close();
      _activeDownloads.remove(model.id);
      await _updateWakelock();
    }
  }

  String _categorizeError(Object e) {
    final str = e.toString().toLowerCase();
    if (str.contains('failed host lookup') ||
        str.contains('socketexception') ||
        str.contains('no address associated')) {
      return 'Network connection failed: Unable to reach host. Please verify that your device has an active Wi-Fi or mobile data connection.';
    } else if (str.contains('connection refused') ||
        str.contains('connection reset')) {
      return 'Connection dropped by server. Please check your network and tap Retry.';
    } else if (str.contains('timed out') || str.contains('timeout')) {
      return 'Connection timed out while contacting server. Please check your connection and tap Retry.';
    } else if (str.contains('404')) {
      return 'Model file not found on server (HTTP 404). Please verify the model URL.';
    } else if (str.contains('401') || str.contains('403')) {
      return 'Access restricted (HTTP 401/403). The model repository may be gated or require an access token.';
    } else if (str.contains('gguf') || str.contains('magic')) {
      return 'Corrupted download: The downloaded file is not a valid GGUF binary.';
    } else if (str.contains('enospc') || str.contains('no space')) {
      return 'Insufficient storage: Device ran out of free space during download.';
    }
    return 'Download failed: ${e.toString().split('\n').first}';
  }

  @override
  Future<void> validateGgufHeader(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('Target file does not exist.');
    }
    final length = await file.length();
    if (length < 4) {
      throw const FormatException(
        'File is too small to be a valid GGUF model.',
      );
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      final header = await raf.read(4);
      if (header.length < 4 ||
          header[0] != 0x47 || // 'G'
          header[1] != 0x47 || // 'G'
          header[2] != 0x55 || // 'U'
          header[3] != 0x46) {
        // 'F'
        throw const FormatException(
          'Corrupted file: Missing GGUF magic bytes (0x47, 0x47, 0x55, 0x46). '
          'The file may be incomplete or an HTML error page.',
        );
      }
    } finally {
      await raf.close();
    }
  }

  @override
  Future<void> copyFileWithProgress(
    String sourcePath,
    String targetPath, {
    void Function(double progress)? onProgress,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Source file not found', sourcePath);
    }

    await validateGgufHeader(sourceFile);

    final totalBytes = await sourceFile.length();
    final targetFile = File(targetPath);
    final targetDir = targetFile.parent;
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final readStream = sourceFile.openRead();
    final writeSink = targetFile.openWrite();

    int copiedBytes = 0;
    try {
      await for (final chunk in readStream) {
        writeSink.add(chunk);
        copiedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(copiedBytes / totalBytes);
        }
      }
      await writeSink.flush();
      await writeSink.close();
    } catch (e) {
      try {
        await writeSink.close();
      } catch (_) {}
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      rethrow;
    }
  }

  @override
  Future<void> pauseDownload(String modelId) async {
    final active = _activeDownloads[modelId];
    if (active != null) {
      active.isPaused = true;
      if (active.completer != null && !active.completer!.isCompleted) {
        active.completer!.complete();
      }
      await active.subscription?.cancel();
      active.client?.close();
      try {
        await active.sink?.flush();
        await active.sink?.close();
      } catch (_) {}
      active.sink = null;
      _activeDownloads.remove(modelId);
      await _updateWakelock();
    }
  }

  @override
  Future<void> cancelDownload(String modelId) async {
    final active = _activeDownloads[modelId];
    if (active != null) {
      active.isCancelled = true;
      if (active.completer != null && !active.completer!.isCompleted) {
        active.completer!.complete();
      }
      await active.subscription?.cancel();
      active.client?.close();
      try {
        await active.sink?.close();
      } catch (_) {}
      active.sink = null;
      final partFile = File(active.partPath);
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {}
      }
      _activeDownloads.remove(modelId);
      await _updateWakelock();

      _emitProgress(
        modelId: modelId,
        status: ModelDownloadStatus.notDownloaded,
        downloadedBytes: 0,
        totalBytes: 0,
        progress: 0.0,
        speedBytesPerSec: 0.0,
      );
    }
  }

  @override
  Future<void> deleteModelFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
    // Also delete leftover .part file if any
    final partFile = File('$filePath.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }

  void _emitProgress({
    required String modelId,
    required ModelDownloadStatus status,
    required int downloadedBytes,
    required int totalBytes,
    required double progress,
    required double speedBytesPerSec,
    String? savedFilePath,
    String? error,
  }) {
    if (!_progressController.isClosed) {
      _progressController.add(
        ModelDownloadProgress(
          modelId: modelId,
          status: status,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          progress: progress,
          speedBytesPerSec: speedBytesPerSec,
          savedFilePath: savedFilePath,
          error: error,
        ),
      );
    }
  }

  @override
  void dispose() {
    for (final active in _activeDownloads.values) {
      active.isCancelled = true;
      active.subscription?.cancel();
      active.client?.close();
      active.sink?.close();
    }
    _activeDownloads.clear();
    _updateWakelock();
    _progressController.close();
  }
}
