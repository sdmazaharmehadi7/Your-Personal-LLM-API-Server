import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/rag/document_attachment.dart';
import '../../models/rag/document_chunk.dart';

abstract class IRagStorageService {
  Future<void> init();
  Future<List<DocumentAttachment>> loadAllDocuments();
  Future<DocumentAttachment?> getDocument(String id);
  Future<DocumentAttachment?> findDocumentByHash(String sha256Hash);
  Future<void> saveDocument(DocumentAttachment document);
  Future<void> deleteDocument(String id);
  Future<void> saveChunks(String documentId, List<DocumentChunk> chunks);
  Future<List<DocumentChunk>> loadChunksForDocuments(List<String> documentIds);
  Future<void> clearAll();
}

class RagStorageService implements IRagStorageService {
  final Directory? customBaseDirectory;
  Directory? _resolvedRagDir;
  bool _isInitialized = false;

  Future<void> _writeQueue = Future.value();

  RagStorageService({this.customBaseDirectory});

  @override
  Future<void> init() async {
    if (_isInitialized && _resolvedRagDir != null) return;

    if (customBaseDirectory != null) {
      _resolvedRagDir = Directory(p.join(customBaseDirectory!.path, 'rag'));
    } else {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        _resolvedRagDir = Directory(
          p.join(appDocDir.path, 'sovereign_ai', 'rag'),
        );
      } catch (_) {
        _resolvedRagDir = Directory(
          p.join(Directory.systemTemp.path, 'sovereign_ai', 'rag'),
        );
      }
    }

    if (!await _resolvedRagDir!.exists()) {
      await _resolvedRagDir!.create(recursive: true);
    }

    final chunksDir = Directory(p.join(_resolvedRagDir!.path, 'chunks'));
    if (!await chunksDir.exists()) {
      await chunksDir.create(recursive: true);
    }

    _isInitialized = true;
  }

  Future<Directory> _ensureDir() async {
    if (!_isInitialized || _resolvedRagDir == null) {
      await init();
    }
    return _resolvedRagDir!;
  }

  File _getDocsFile(Directory dir) => File(p.join(dir.path, 'documents.json'));
  File _getChunkFile(Directory dir, String docId) =>
      File(p.join(dir.path, 'chunks', '$docId.json'));

  @override
  Future<List<DocumentAttachment>> loadAllDocuments() async {
    final dir = await _ensureDir();
    final file = _getDocsFile(dir);
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final decoded = jsonDecode(content) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => DocumentAttachment.fromJson(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<DocumentAttachment?> getDocument(String id) async {
    final all = await loadAllDocuments();
    return all.where((d) => d.id == id).firstOrNull;
  }

  @override
  Future<DocumentAttachment?> findDocumentByHash(String sha256Hash) async {
    if (sha256Hash.isEmpty) return null;
    final all = await loadAllDocuments();
    return all
        .where(
          (d) =>
              d.sha256Hash == sha256Hash && d.status == DocumentStatus.indexed,
        )
        .firstOrNull;
  }

  @override
  Future<void> saveDocument(DocumentAttachment document) async {
    final dir = await _ensureDir();
    _writeQueue = _writeQueue.then((_) async {
      final all = await loadAllDocuments();
      final index = all.indexWhere((d) => d.id == document.id);
      if (index != -1) {
        all[index] = document;
      } else {
        all.add(document);
      }

      final file = _getDocsFile(dir);
      final tmpFile = File('${file.path}.tmp');
      final jsonStr = jsonEncode(all.map((d) => d.toJson()).toList());
      await tmpFile.writeAsString(jsonStr, flush: true);
      await tmpFile.rename(file.path);
    });
    return _writeQueue;
  }

  @override
  Future<void> deleteDocument(String id) async {
    final dir = await _ensureDir();
    _writeQueue = _writeQueue.then((_) async {
      final all = await loadAllDocuments();
      all.removeWhere((d) => d.id == id);

      final file = _getDocsFile(dir);
      final tmpFile = File('${file.path}.tmp');
      final jsonStr = jsonEncode(all.map((d) => d.toJson()).toList());
      await tmpFile.writeAsString(jsonStr, flush: true);
      await tmpFile.rename(file.path);

      final chunkFile = _getChunkFile(dir, id);
      if (await chunkFile.exists()) {
        try {
          await chunkFile.delete();
        } catch (_) {}
      }
    });
    return _writeQueue;
  }

  @override
  Future<void> saveChunks(String documentId, List<DocumentChunk> chunks) async {
    final dir = await _ensureDir();
    _writeQueue = _writeQueue.then((_) async {
      final chunkFile = _getChunkFile(dir, documentId);
      final tmpFile = File('${chunkFile.path}.tmp');
      final jsonStr = jsonEncode(chunks.map((c) => c.toJson()).toList());
      await tmpFile.writeAsString(jsonStr, flush: true);
      await tmpFile.rename(chunkFile.path);
    });
    return _writeQueue;
  }

  @override
  Future<List<DocumentChunk>> loadChunksForDocuments(
    List<String> documentIds,
  ) async {
    if (documentIds.isEmpty) return [];
    final dir = await _ensureDir();
    final allChunks = <DocumentChunk>[];

    for (final docId in documentIds) {
      final chunkFile = _getChunkFile(dir, docId);
      if (!await chunkFile.exists()) continue;

      try {
        final content = await chunkFile.readAsString();
        if (content.trim().isEmpty) continue;
        final decoded = jsonDecode(content) as List<dynamic>;
        final chunks = decoded.whereType<Map<String, dynamic>>().map(
          (m) => DocumentChunk.fromJson(m),
        );
        allChunks.addAll(chunks);
      } catch (_) {}
    }

    return allChunks;
  }

  @override
  Future<void> clearAll() async {
    final dir = await _ensureDir();
    _writeQueue = _writeQueue.then((_) async {
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
          await dir.create(recursive: true);
          final chunksDir = Directory(p.join(dir.path, 'chunks'));
          await chunksDir.create(recursive: true);
        } catch (_) {}
      }
    });
    return _writeQueue;
  }
}
