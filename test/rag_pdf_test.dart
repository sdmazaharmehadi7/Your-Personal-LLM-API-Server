import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:archive/archive.dart';

void main() {
  test('Syncfusion PDF extraction works in Flutter environment', () {
    final doc = PdfDocument();
    final page = doc.pages.add();
    page.graphics.drawString(
      'Sovereign AI Offline RAG Test Page Content',
      PdfStandardFont(PdfFontFamily.helvetica, 12),
    );
    final Uint8List bytes = Uint8List.fromList(doc.saveSync());
    doc.dispose();
    expect(bytes, isNotEmpty);

    final loadedDoc = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(loadedDoc).extractText();
    final pageCount = loadedDoc.pages.count;
    loadedDoc.dispose();

    expect(pageCount, equals(1));
    expect(text, contains('Sovereign AI Offline RAG Test Page Content'));
  });

  test('Archive DOCX extraction works in Flutter environment', () {
    final archive = Archive();
    final xmlContent =
        '<w:document><w:body><w:p><w:r><w:t>Testing Sovereign DOCX Parser</w:t></w:r></w:p></w:body></w:document>';
    archive.addFile(
      ArchiveFile('word/document.xml', xmlContent.length, xmlContent.codeUnits),
    );
    final zipBytes = ZipEncoder().encode(archive);
    expect(zipBytes, isNotNull);

    final decoded = ZipDecoder().decodeBytes(zipBytes);
    final docXml = decoded.findFile('word/document.xml');
    expect(docXml, isNotNull);
    final content = String.fromCharCodes(docXml!.content as List<int>);
    expect(content, contains('Testing Sovereign DOCX Parser'));
  });
}
