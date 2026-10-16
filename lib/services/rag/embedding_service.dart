import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:llamadart/llamadart.dart';

abstract class IEmbeddingService {
  bool get isLoaded;
  String? get currentModelPath;
  String? get currentModelId;
  int get embeddingDimension;

  Future<void> loadModel(
    String filePath, {
    String? modelId,
    int contextWindow = 512,
    bool useGpu = false,
  });

  Future<void> unloadModel();

  Future<List<double>> embedText(String text);

  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    int batchSize = 8,
  });

  double cosineSimilarity(List<double> v1, List<double> v2);

  List<double> normalizeVector(List<double> vector);
}

class EmbeddingException implements Exception {
  final String message;
  const EmbeddingException(this.message);

  @override
  String toString() => message;
}

class LocalEmbeddingService implements IEmbeddingService {
  static const int defaultDimension = 384;

  LlamaEngine? _engine;
  String? _currentModelPath;
  String? _currentModelId;
  int _embeddingDimension = defaultDimension;
  bool _isLoading = false;
  Future<void> _executionQueue = Future.value();

  bool get isLoading => _isLoading;

  @override
  bool get isLoaded => _engine != null;

  @override
  String? get currentModelPath => _currentModelPath;

  @override
  String? get currentModelId => _currentModelId;

  @override
  int get embeddingDimension => _embeddingDimension;

  @override
  Future<void> loadModel(
    String filePath, {
    String? modelId,
    int contextWindow = 512,
    bool useGpu = false,
  }) async {
    if (kIsWeb) {
      throw const EmbeddingException(
        'On-device neural embedding inference is not supported in web browser environments.',
      );
    }

    final trimmedPath = filePath.trim();
    if (trimmedPath.isEmpty) {
      throw const EmbeddingException('No embedding model path provided.');
    }

    final file = File(trimmedPath);
    if (!await file.exists()) {
      throw EmbeddingException('Embedding model file not found at "$trimmedPath".');
    }

    if (file.lengthSync() < 1024 * 1024) {
      throw const EmbeddingException('Selected file is too small to be a valid GGUF embedding model.');
    }

    await unloadModel();
    _isLoading = true;

    try {
      final modelSource = ModelSource.parse(trimmedPath);
      final model = LlamaModel(modelSource);

      final modelParams = ModelParams(
        contextSize: contextWindow > 0 ? contextWindow : 512,
        gpuLayers: useGpu ? 99 : 0,
      );

      _engine = await LlamaEngine.load(model, params: modelParams);
      _currentModelPath = trimmedPath;
      _currentModelId = modelId ?? 'all-MiniLM-L6-v2';

      // Probe actual vector dimension with a micro warm-up token
      try {
        final probeVec = await _engine!.embed('test', normalize: true);
        if (probeVec.isNotEmpty) {
          _embeddingDimension = probeVec.length;
        }
      } catch (_) {
        _embeddingDimension = defaultDimension;
      }
    } catch (e) {
      await unloadModel();
      throw EmbeddingException('Failed to load neural embedding model: $e');
    } finally {
      _isLoading = false;
    }
  }

  @override
  Future<void> unloadModel() async {
    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {
        // Ignore native disposal errors during cleanup
      } finally {
        _engine = null;
        _currentModelPath = null;
        _currentModelId = null;
        _embeddingDimension = defaultDimension;
      }
    }
  }

  @override
  Future<List<double>> embedText(String text) {
    return _queueOperation(() async {
      if (_engine == null) {
        throw const EmbeddingException('No embedding model is loaded.');
      }

      final cleanText = text.trim();
      if (cleanText.isEmpty) {
        return List<double>.filled(_embeddingDimension, 0.0);
      }

      try {
        final vector = await _engine!.embed(cleanText, normalize: true);
        if (vector.isEmpty) {
          return List<double>.filled(_embeddingDimension, 0.0);
        }
        return normalizeVector(vector);
      } catch (e) {
        throw EmbeddingException('Neural embedding failed for text: $e');
      }
    });
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    int batchSize = 8,
  }) {
    return _queueOperation(() async {
      if (_engine == null) {
        throw const EmbeddingException('No embedding model is loaded.');
      }

      if (texts.isEmpty) return const <List<double>>[];

      final allEmbeddings = <List<double>>[];

      // Process in bounded batches to avoid blowing native memory on mobile devices
      for (int i = 0; i < texts.length; i += batchSize) {
        final end = math.min(i + batchSize, texts.length);
        final batch = texts.sublist(i, end);

        try {
          final batchVectors = await _engine!.embedBatch(batch, normalize: true);
          for (final vec in batchVectors) {
            allEmbeddings.add(normalizeVector(vec));
          }
        } catch (_) {
          // Fallback to sequential calls if batch dispatch encounters an issue
          for (final t in batch) {
            final vec = await _engine!.embed(t.trim(), normalize: true);
            allEmbeddings.add(normalizeVector(vec));
          }
        }
      }

      return allEmbeddings;
    });
  }

  @override
  double cosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.isEmpty || v2.isEmpty || v1.length != v2.length) {
      return 0.0;
    }

    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;

    for (int i = 0; i < v1.length; i++) {
      final a = v1[i];
      final b = v2[i];
      dotProduct += a * b;
      norm1 += a * a;
      norm2 += b * b;
    }

    if (norm1 <= 0.0 || norm2 <= 0.0) return 0.0;
    final denominator = math.sqrt(norm1) * math.sqrt(norm2);
    if (denominator <= 0.0) return 0.0;

    final similarity = dotProduct / denominator;
    return similarity.clamp(-1.0, 1.0);
  }

  @override
  List<double> normalizeVector(List<double> vector) {
    if (vector.isEmpty) return vector;

    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }

    if (sumSq <= 0.0) return List<double>.from(vector);
    final norm = math.sqrt(sumSq);

    return vector.map((v) => v / norm).toList();
  }

  Future<T> _queueOperation<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _executionQueue = _executionQueue.then((_) async {
      try {
        final result = await op();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }
}
