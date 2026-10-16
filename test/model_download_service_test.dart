import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sovereign_ai/models/local_model.dart';
import 'package:sovereign_ai/services/model_download_service.dart';
import 'package:sovereign_ai/services/storage_service.dart';
import 'package:sovereign_ai/state/model_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sovereign_dl_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // Valid GGUF file bytes: 'G', 'G', 'U', 'F' followed by dummy data
  final validGgufBytes = [
    0x47,
    0x47,
    0x55,
    0x46,
    0x01,
    0x00,
    0x00,
    0x00,
    0x10,
    0x20,
  ];
  // Invalid non-GGUF bytes (e.g., HTML 404 response): '<html>'
  final invalidHtmlBytes = utf8.encode(
    '<html><head><title>404 Not Found</title></head></html>',
  );

  group('ModelDownloadService tests', () {
    test(
      'successfully downloads valid GGUF model and validates header',
      () async {
        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.fromIterable([validGgufBytes]),
            200,
            contentLength: validGgufBytes.length,
          );
        });

        final service = ModelDownloadService(clientFactory: () => mockClient);
        final model = const LocalModel(
          id: 'test-model',
          name: 'Test Model',
          family: 'Test',
          parameterSize: '100M',
          quantization: 'Q4_K_M',
          diskSizeGb: 0.1,
          estimatedRamGb: 0.2,
          description: 'Test description',
          filename: 'test-model.gguf',
          downloadUrl: 'https://example.com/test-model.gguf',
        );

        final progressEvents = <ModelDownloadProgress>[];
        final sub = service.progressStream.listen(progressEvents.add);

        await service.startDownload(model, tempDir.path);

        await Future.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        service.dispose();

        expect(progressEvents, isNotEmpty);
        final last = progressEvents.last;
        expect(last.status, ModelDownloadStatus.downloaded);
        expect(last.progress, 1.0);
        expect(last.downloadedBytes, validGgufBytes.length);

        final finalFile = File('${tempDir.path}/${model.filename}');
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.length(), validGgufBytes.length);
      },
    );

    test(
      'rejects download if magic bytes are not GGUF (e.g. 404 HTML)',
      () async {
        final mockClient = MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.fromIterable([invalidHtmlBytes]),
            200,
            contentLength: invalidHtmlBytes.length,
          );
        });

        final service = ModelDownloadService(clientFactory: () => mockClient);
        final model = const LocalModel(
          id: 'bad-model',
          name: 'Bad Model',
          family: 'Test',
          parameterSize: '100M',
          quantization: 'Q4_K_M',
          diskSizeGb: 0.1,
          estimatedRamGb: 0.2,
          description: 'Bad model',
          filename: 'bad-model.gguf',
          downloadUrl: 'https://example.com/bad-model.gguf',
        );

        final progressEvents = <ModelDownloadProgress>[];
        final sub = service.progressStream.listen(progressEvents.add);

        await service.startDownload(model, tempDir.path);

        await Future.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        service.dispose();

        expect(progressEvents, isNotEmpty);
        final last = progressEvents.last;
        expect(last.status, ModelDownloadStatus.error);
        expect(last.error, contains('GGUF'));

        final finalFile = File('${tempDir.path}/${model.filename}');
        expect(await finalFile.exists(), isFalse);
      },
    );

    test('cancelling download deletes partial .part file', () async {
      final controller = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          controller.stream,
          200,
          contentLength: 1000,
        );
      });

      final service = ModelDownloadService(clientFactory: () => mockClient);
      final model = const LocalModel(
        id: 'cancel-model',
        name: 'Cancel Model',
        family: 'Test',
        parameterSize: '100M',
        quantization: 'Q4_K_M',
        diskSizeGb: 0.1,
        estimatedRamGb: 0.2,
        description: 'Cancel model',
        filename: 'cancel-model.gguf',
        downloadUrl: 'https://example.com/cancel-model.gguf',
      );

      final downloadFuture = service.startDownload(model, tempDir.path);

      // Add a chunk
      controller.add([0x47, 0x47, 0x55, 0x46]);
      await Future.delayed(const Duration(milliseconds: 50));

      final partFile = File('${tempDir.path}/${model.filename}.part');
      expect(await partFile.exists(), isTrue);

      await service.cancelDownload(model.id);
      await controller.close();
      await downloadFuture;

      expect(await partFile.exists(), isFalse);
      service.dispose();
    });

    test('deleting model file removes it from filesystem', () async {
      final service = ModelDownloadService();
      final testFile = File('${tempDir.path}/to_delete.gguf');
      await testFile.writeAsBytes(validGgufBytes);
      expect(await testFile.exists(), isTrue);

      await service.deleteModelFile(testFile.path);
      expect(await testFile.exists(), isFalse);
      service.dispose();
    });

    test('URL validator converts Hugging Face blob links to resolve links', () {
      const blobUrl =
          'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/blob/main/qwen2.5-0.5b-instruct-q4_k_m.gguf';
      final res = ModelDownloadService.validateAndResolveUrl(blobUrl);

      expect(res.isValid, isTrue);
      expect(
        res.resolvedUrl,
        'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf',
      );
      expect(res.suggestedFilename, 'qwen2.5-0.5b-instruct-q4_k_m.gguf');
    });

    test('URL validator detects repo overview page without GGUF filename', () {
      const repoUrl = 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF';
      final res = ModelDownloadService.validateAndResolveUrl(repoUrl);

      expect(res.isValid, isFalse);
      expect(res.error, contains('Files'));
    });
  });

  group('ModelState model catalog and lifecycle tests', () {
    test('ModelState catalog initializes with curated models', () {
      final state = ModelState();
      expect(state.models.length, greaterThanOrEqualTo(6));

      final smol = state.models.firstWhere((m) => m.id == 'smollm2-135m-q4');
      expect(smol.name, 'SmolLM2 135M Instruct');
      expect(smol.publisher, 'HuggingFaceTB');
      expect(smol.minRamGb, 0.5);
      expect(smol.downloadUrl, isNotNull);

      final qwen15 = state.models.firstWhere((m) => m.id == 'qwen-2.5-1.5b-q4');
      expect(qwen15.name, contains('1.5B'));

      final gemma = state.models.firstWhere(
        (m) => m.id == 'gemma-2-2b-it-abliterated-q4',
      );
      expect(gemma.name, contains('Abliterated'));
      expect(gemma.downloadUrl, isNotNull);

      state.dispose();
    });

    test(
      'ModelState discovers existing GGUF models in storage directory',
      () async {
        final preFile = File(
          p.join(tempDir.path, 'smollm2-135m-instruct-q4_k_m.gguf'),
        );
        await preFile.writeAsBytes(validGgufBytes);

        final state = ModelState(modelsDirectory: tempDir.path);
        await state.init();

        final smol = state.models.firstWhere((m) => m.id == 'smollm2-135m-q4');
        expect(smol.downloadStatus, ModelDownloadStatus.downloaded);
        expect(
          p.canonicalize(smol.localPath!),
          equals(p.canonicalize(preFile.path)),
        );

        state.dispose();
      },
    );

    test(
      'ModelState imports local GGUF file with validation and copy',
      () async {
        final externalDir = await Directory.systemTemp.createTemp('ext_');
        final externalFile = File(
          p.join(externalDir.path, 'custom_model.gguf'),
        );
        await externalFile.writeAsBytes(validGgufBytes);

        final storage = InMemoryStorageService();
        final state = ModelState(
          modelsDirectory: tempDir.path,
          storageService: storage,
        );
        await state.init();

        final importedCount = await state.importLocalFiles([externalFile.path]);
        expect(importedCount, 1);

        final imported = state.models.firstWhere(
          (m) => m.filename == 'custom_model.gguf',
        );
        expect(imported.sourceType, ModelSourceType.imported);
        expect(imported.downloadStatus, ModelDownloadStatus.downloaded);
        expect(
          File(p.join(tempDir.path, 'custom_model.gguf')).existsSync(),
          isTrue,
        );

        // Verify custom models were persisted in storage
        final loaded = await storage.loadCustomModels();
        expect(loaded.any((m) => m.filename == 'custom_model.gguf'), isTrue);

        await externalDir.delete(recursive: true);
        state.dispose();
      },
    );

    test(
      'ModelState deleteModel resets catalog item and deletes file',
      () async {
        final preFile = File(
          p.join(tempDir.path, 'smollm2-135m-instruct-q4_k_m.gguf'),
        );
        await preFile.writeAsBytes(validGgufBytes);

        final state = ModelState(modelsDirectory: tempDir.path);
        await state.init();

        final smol = state.models.firstWhere((m) => m.id == 'smollm2-135m-q4');
        expect(smol.downloadStatus, ModelDownloadStatus.downloaded);

        await state.deleteModel(smol);

        final updatedSmol = state.models.firstWhere(
          (m) => m.id == 'smollm2-135m-q4',
        );
        expect(updatedSmol.downloadStatus, ModelDownloadStatus.notDownloaded);
        expect(updatedSmol.localPath, isNull);
        expect(await preFile.exists(), isFalse);

        state.dispose();
      },
    );
  });
}
