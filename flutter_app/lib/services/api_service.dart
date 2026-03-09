import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/pdf_document.dart';

class ApiService {
  static const String _baseUrl = 'http://localhost:8000';
  late final Dio _dio;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false, error: true));
  }

  Future<PdfDocument> uploadPdf(File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path, filename: file.path.split(Platform.pathSeparator).last),
    });
    final r = await _dio.post('/upload', data: formData);
    return PdfDocument.fromJson(r.data);
  }

  Future<Map<String, dynamic>> getPdfInfo(String fileId) async {
    final r = await _dio.get('/info/$fileId');
    return Map<String, dynamic>.from(r.data);
  }

  Future<Map<String, dynamic>> getPageImageFull(String fileId, int page, {int dpi = 150}) async {
    final r = await _dio.get('/page/$fileId/$page?dpi=$dpi');
    return Map<String, dynamic>.from(r.data);
  }

  Future<String> getPageImage(String fileId, int page, {int dpi = 150}) async {
    final d = await getPageImageFull(fileId, page, dpi: dpi);
    return d['image_base64'] as String;
  }

  Future<List<TextBlock>> getPageTextBlocks(String fileId, int page) async {
    final r = await _dio.get('/text/$fileId/$page');
    final blocks = r.data['blocks'] as List;
    return blocks.map((b) => TextBlock.fromJson(Map<String, dynamic>.from(b))).toList();
  }

  // ── Inline text edit (click text → edit in place) ──
  Future<Map<String, dynamic>> editTextInline({
    required String fileId,
    required int pageNumber,
    required String searchText,
    required String replacementText,
    double? regionX0, double? regionY0, double? regionX1, double? regionY1,
    String? fontName, double? fontSize, String? fontColor,
    bool? bold, bool? italic,
  }) async {
    final r = await _dio.post('/edit_text', data: {
      'file_id': fileId, 'page_number': pageNumber,
      'search_text': searchText, 'replacement_text': replacementText,
      if (regionX0 != null) 'region_x0': regionX0,
      if (regionY0 != null) 'region_y0': regionY0,
      if (regionX1 != null) 'region_x1': regionX1,
      if (regionY1 != null) 'region_y1': regionY1,
      if (fontName != null) 'font_name': fontName,
      if (fontSize != null) 'font_size': fontSize,
      if (fontColor != null) 'font_color': fontColor,
      if (bold != null) 'bold': bold,
      if (italic != null) 'italic': italic,
    });
    return Map<String, dynamic>.from(r.data);
  }

  // ── Insert new text block ──
  Future<bool> insertTextBlock({
    required String fileId, required int pageNumber, required String text,
    required double x, required double y,
    double width = 200, double height = 50,
    String fontName = 'helv', double fontSize = 12,
    String fontColor = '#000000', String? bgColor,
    bool bold = false, bool italic = false, String align = 'left',
  }) async {
    final r = await _dio.post('/insert_text', data: {
      'file_id': fileId, 'page_number': pageNumber, 'text': text,
      'x': x, 'y': y, 'width': width, 'height': height,
      'font_name': fontName, 'font_size': fontSize, 'font_color': fontColor,
      if (bgColor != null) 'bg_color': bgColor,
      'bold': bold, 'italic': italic, 'align': align,
    });
    return r.data['success'] == true;
  }

  // ── Find & Replace ──
  Future<int> findAndReplace({
    required String fileId, required String findText, required String replaceText,
    bool caseSensitive = false, bool wholeWord = false,
    bool allPages = true, int? pageNumber,
  }) async {
    final r = await _dio.post('/find_replace', data: {
      'file_id': fileId, 'find_text': findText, 'replace_text': replaceText,
      'case_sensitive': caseSensitive, 'whole_word': wholeWord,
      'all_pages': allPages,
      if (pageNumber != null) 'page_number': pageNumber,
    });
    return r.data['total_replaced'] as int? ?? 0;
  }

  // ── Delete region ──
  Future<bool> deleteRegion({
    required String fileId, required int pageNumber,
    required double x0, required double y0, required double x1, required double y1,
    String fillColor = '#FFFFFF',
  }) async {
    final r = await _dio.post('/delete_region', data: {
      'file_id': fileId, 'page_number': pageNumber,
      'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1, 'fill_color': fillColor,
    });
    return r.data['success'] == true;
  }

  // ── Insert image ──
  Future<bool> insertImage({
    required String fileId, required int pageNumber, required String imageBase64,
    required double x, required double y, required double width, required double height,
  }) async {
    final r = await _dio.post('/insert_image', data: {
      'file_id': fileId, 'page_number': pageNumber, 'image_base64': imageBase64,
      'x': x, 'y': y, 'width': width, 'height': height,
    });
    return r.data['success'] == true;
  }

  // ── Undo / Redo ──
  Future<bool> undo(String fileId) async {
    try { final r = await _dio.post('/undo/$fileId'); return r.data['success'] == true; }
    catch (_) { return false; }
  }

  Future<bool> redo(String fileId) async {
    try { final r = await _dio.post('/redo/$fileId'); return r.data['success'] == true; }
    catch (_) { return false; }
  }

  // ── Annotations ──
  Future<bool> addAnnotation({
    required String fileId, required int page, required String type,
    String? content, required double x, required double y,
    double? width, double? height, String color = '#FFFF00', int fontSize = 12,
  }) async {
    final r = await _dio.post('/annotate', data: {
      'file_id': fileId, 'page_number': page, 'annotation_type': type,
      'content': content, 'x': x, 'y': y,
      'width': width, 'height': height, 'color': color, 'font_size': fontSize,
    });
    return r.data['success'] == true;
  }

  // ── Page ops ──
  Future<bool> rotatePage(String fileId, int page, int degrees) async {
    final r = await _dio.post('/rotate', data: {'file_id': fileId, 'page_number': page, 'degrees': degrees});
    return r.data['success'] == true;
  }

  Future<bool> addBlankPage(String fileId, int afterPage) async {
    final r = await _dio.post('/add_page', data: {'file_id': fileId, 'after_page': afterPage});
    return r.data['success'] == true;
  }

  Future<bool> deletePage(String fileId, int pageNumber) async {
    final r = await _dio.post('/delete_page', data: {'file_id': fileId, 'page_number': pageNumber});
    return r.data['success'] == true;
  }

  Future<String?> mergePdfs(List<String> fileIds) async {
    final r = await _dio.post('/merge', data: {'file_ids': fileIds});
    return r.data['file_id'] as String?;
  }

  Future<List<Map<String, dynamic>>> splitPdf(String fileId, List<String> pageRanges) async {
    final r = await _dio.post('/split', data: {'file_id': fileId, 'page_ranges': pageRanges});
    return List<Map<String, dynamic>>.from(r.data['parts']);
  }

  Future<bool> addWatermark(String fileId, String text, {
    double opacity = 0.3, int fontSize = 40, String color = '#FF0000',
  }) async {
    final r = await _dio.post('/watermark', data: {
      'file_id': fileId, 'text': text, 'opacity': opacity, 'font_size': fontSize, 'color': color,
    });
    return r.data['success'] == true;
  }

  Future<bool> protectPdf(String fileId, String password) async {
    final r = await _dio.post('/protect', data: {'file_id': fileId, 'password': password});
    return r.data['success'] == true;
  }

  Future<File?> downloadPdf(String fileId, String savePath) async {
    await _dio.download('/download/$fileId', savePath);
    return File(savePath);
  }

  String getDownloadUrl(String fileId) => '$_baseUrl/download/$fileId';
}

// ── TextBlock model ───────────────────────────────────────────────────────────
class TextBlock {
  final String text;
  final double x0, y0, x1, y1;
  final String font;
  final double size;
  final int colorInt;
  final int flags;

  const TextBlock({
    required this.text, required this.x0, required this.y0,
    required this.x1, required this.y1, required this.font,
    required this.size, required this.colorInt, required this.flags,
  });

  factory TextBlock.fromJson(Map<String, dynamic> j) => TextBlock(
    text: j['text'] ?? '', font: j['font'] ?? '',
    x0: (j['x0'] ?? 0).toDouble(), y0: (j['y0'] ?? 0).toDouble(),
    x1: (j['x1'] ?? 0).toDouble(), y1: (j['y1'] ?? 0).toDouble(),
    size: (j['size'] ?? 12).toDouble(), colorInt: j['color'] ?? 0, flags: j['flags'] ?? 0,
  );

  bool get isBold => (flags & 16) != 0;
  bool get isItalic => (flags & 2) != 0;
  double get width => x1 - x0;
  double get height => y1 - y0;
}