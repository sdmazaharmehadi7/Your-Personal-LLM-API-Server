import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ParsedPage {
  final int pageNumber;
  final String text;

  const ParsedPage({required this.pageNumber, required this.text});
}

class ParsedDocument {
  final String fileName;
  final String fileExtension;
  final int fileSizeBytes;
  final String sha256Hash;
  final List<ParsedPage> pages;
  final String fullText;
  final bool isScanned;
  final int pageCount;

  const ParsedDocument({
    required this.fileName,
    required this.fileExtension,
    required this.fileSizeBytes,
    required this.sha256Hash,
    required this.pages,
    required this.fullText,
    required this.isScanned,
    required this.pageCount,
  });
}

class DocumentParsingException implements Exception {
  final String message;
  const DocumentParsingException(this.message);

  @override
  String toString() => message;
}

class DocumentParserService {
  static const int defaultMaxSizeBytes = 25 * 1024 * 1024; // 25 MB limit
  final int maxSizeBytes;

  const DocumentParserService({this.maxSizeBytes = defaultMaxSizeBytes});

  static const supportedExtensions = {
    'pdf',
    'txt',
    'md',
    'markdown',
    'docx',
    'csv',
    'json',
    'log',
  };

  bool isSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return supportedExtensions.contains(ext);
  }

  Future<ParsedDocument> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw DocumentParsingException('File not found at "$filePath"');
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      throw const DocumentParsingException(
        'The selected file is empty (0 bytes).',
      );
    }

    if (fileSize > maxSizeBytes) {
      final sizeMb = (fileSize / (1024 * 1024)).toStringAsFixed(1);
      final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);
      throw DocumentParsingException(
        'File size ($sizeMb MB) exceeds the maximum allowed limit of $maxMb MB.',
      );
    }

    final fileName = p.basename(filePath);
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    if (!supportedExtensions.contains(ext)) {
      throw DocumentParsingException(
        'Unsupported file format ".$ext". Supported formats are: ${supportedExtensions.join(', ')}.',
      );
    }

    final bytes = await file.readAsBytes();
    final sha256Hash = sha256.convert(bytes).toString();

    switch (ext) {
      case 'pdf':
        return _parsePdf(bytes, fileName, ext, fileSize, sha256Hash);
      case 'docx':
        return _parseDocx(bytes, fileName, ext, fileSize, sha256Hash);
      case 'csv':
      case 'json':
      case 'log':
      case 'txt':
      case 'md':
      case 'markdown':
      default:
        return _parsePlainText(bytes, fileName, ext, fileSize, sha256Hash);
    }
  }

  ParsedDocument _parsePdf(
    Uint8List bytes,
    String fileName,
    String ext,
    int fileSize,
    String sha256Hash,
  ) {
    PdfDocument? pdfDoc;
    try {
      pdfDoc = PdfDocument(inputBytes: bytes);
      final totalPages = pdfDoc.pages.count;
      if (totalPages == 0) {
        throw const DocumentParsingException('PDF contains no pages.');
      }

      final pages = <ParsedPage>[];
      final extractor = PdfTextExtractor(pdfDoc);
      final fullTextBuffer = StringBuffer();

      for (int i = 0; i < totalPages; i++) {
        // extractText by page index (0-based)
        final pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        final normalized = _normalizeText(pageText);
        if (normalized.isNotEmpty) {
          fullTextBuffer.writeln(normalized);
        }
        pages.add(ParsedPage(pageNumber: i + 1, text: normalized));
      }

      final combined = fullTextBuffer.toString().trim();
      // Scanned PDF detection: if multiple pages have almost no extracted text
      final bool isScanned = totalPages > 0 && combined.length < 15;

      if (isScanned) {
        throw DocumentParsingException(
          'No selectable text found in "$fileName". It appears to be a scanned image or photo PDF. '
          'Local offline OCR is not yet available; please use a text-searchable PDF.',
        );
      }

      return ParsedDocument(
        fileName: fileName,
        fileExtension: ext,
        fileSizeBytes: fileSize,
        sha256Hash: sha256Hash,
        pages: pages,
        fullText: combined,
        isScanned: false,
        pageCount: totalPages,
      );
    } on DocumentParsingException {
      rethrow;
    } catch (e) {
      final err = e.toString().toLowerCase();
      if (err.contains('password') || err.contains('encrypt')) {
        throw DocumentParsingException(
          'PDF "$fileName" is password-protected or encrypted.',
        );
      }
      throw DocumentParsingException('Failed to read PDF "$fileName": $e');
    } finally {
      pdfDoc?.dispose();
    }
  }

  ParsedDocument _parseDocx(
    Uint8List bytes,
    String fileName,
    String ext,
    int fileSize,
    String sha256Hash,
  ) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final documentXmlFile = archive.findFile('word/document.xml');
      if (documentXmlFile == null) {
        throw const DocumentParsingException(
          'Invalid DOCX format: word/document.xml missing.',
        );
      }

      final xmlString = utf8.decode(
        documentXmlFile.content as List<int>,
        allowMalformed: true,
      );

      final extractedText = _extractTextFromDocxXml(xmlString);
      final normalized = _normalizeText(extractedText);

      if (normalized.trim().isEmpty) {
        throw DocumentParsingException(
          'Document "$fileName" contains no readable text.',
        );
      }

      return ParsedDocument(
        fileName: fileName,
        fileExtension: ext,
        fileSizeBytes: fileSize,
        sha256Hash: sha256Hash,
        pages: [ParsedPage(pageNumber: 1, text: normalized)],
        fullText: normalized,
        isScanned: false,
        pageCount: 1,
      );
    } on DocumentParsingException {
      rethrow;
    } catch (e) {
      throw DocumentParsingException('Failed to parse DOCX "$fileName": $e');
    }
  }

  ParsedDocument _parsePlainText(
    Uint8List bytes,
    String fileName,
    String ext,
    int fileSize,
    String sha256Hash,
  ) {
    String rawText;
    try {
      rawText = utf8.decode(bytes);
    } catch (_) {
      // Fallback for Latin-1 / ASCII encoded files
      rawText = latin1.decode(bytes);
    }

    final normalized = _normalizeText(rawText);
    if (normalized.trim().isEmpty) {
      throw DocumentParsingException(
        'File "$fileName" contains no readable text.',
      );
    }

    return ParsedDocument(
      fileName: fileName,
      fileExtension: ext,
      fileSizeBytes: fileSize,
      sha256Hash: sha256Hash,
      pages: [ParsedPage(pageNumber: 1, text: normalized)],
      fullText: normalized,
      isScanned: false,
      pageCount: 1,
    );
  }

  String _extractTextFromDocxXml(String xml) {
    final buffer = StringBuffer();
    // Split by paragraphs <w:p ...> or </w:p>
    final pRegex = RegExp(r'<w:p[\s>].*?</w:p>', dotAll: true);
    final matches = pRegex.allMatches(xml);

    if (matches.isEmpty) {
      // Fallback: extract all <w:t> tags
      final tRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
      for (final m in tRegex.allMatches(xml)) {
        buffer.write(m.group(1));
        buffer.write(' ');
      }
    } else {
      final tRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
      for (final pMatch in matches) {
        final pContent = pMatch.group(0) ?? '';
        final pText = StringBuffer();
        for (final tMatch in tRegex.allMatches(pContent)) {
          pText.write(tMatch.group(1));
        }
        final line = pText.toString().trim();
        if (line.isNotEmpty) {
          buffer.writeln(line);
        }
      }
    }

    return buffer.toString();
  }

  String _normalizeText(String input) {
    // Replace carriage returns with standard newlines
    var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // Normalize consecutive spaces/tabs on the same line to a single space
    text = text.replaceAll(RegExp(r'[ \t]+'), ' ');
    // Limit consecutive empty lines to maximum 2
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }
}
