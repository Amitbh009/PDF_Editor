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
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Content-Type': 'application/json'},
    ));

    // Logging interceptor (debug only)
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      error: true,
    ));
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  Future<PdfDocument> uploadPdf(File file) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });

    final response = await _dio.post('/upload', data: formData);
    return PdfDocument.fromJson(response.data);
  }

  // ─── Info ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPdfInfo(String fileId) async {
    final response = await _dio.get('/info/$fileId');
    return response.data;
  }

  // ─── Page Rendering ────────────────────────────────────────────────────────

  Future<String> getPageImage(String fileId, int page, {int dpi = 150}) async {
    final response = await _dio.get('/page/$fileId/$page?dpi=$dpi');
    return response.data['image_base64'] as String;
  }

  Future<Map<String, dynamic>> extractPageText(String fileId, int page) async {
    final response = await _dio.get('/text/$fileId/$page');
    return response.data;
  }

  // ─── Annotations ──────────────────────────────────────────────────────────

  Future<bool> addAnnotation({
    required String fileId,
    required int page,
    required String type,
    String? content,
    required double x,
    required double y,
    double? width,
    double? height,
    String color = '#FFFF00',
    int fontSize = 12,
  }) async {
    final response = await _dio.post('/annotate', data: {
      'file_id': fileId,
      'page_number': page,
      'annotation_type': type,
      'content': content,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'color': color,
      'font_size': fontSize,
    });
    return response.data['success'] == true;
  }

  // ─── Merge & Split ────────────────────────────────────────────────────────

  Future<String?> mergePdfs(List<String> fileIds) async {
    final response = await _dio.post('/merge', data: {
      'file_ids': fileIds,
    });
    return response.data['file_id'] as String?;
  }

  Future<List<Map<String, dynamic>>> splitPdf(
    String fileId,
    List<String> pageRanges,
  ) async {
    final response = await _dio.post('/split', data: {
      'file_id': fileId,
      'page_ranges': pageRanges,
    });
    return List<Map<String, dynamic>>.from(response.data['parts']);
  }

  // ─── Transformations ──────────────────────────────────────────────────────

  Future<bool> rotatePage(String fileId, int page, int degrees) async {
    final response = await _dio.post('/rotate', data: {
      'file_id': fileId,
      'page_number': page,
      'degrees': degrees,
    });
    return response.data['success'] == true;
  }

  Future<bool> addWatermark(String fileId, String text, {
    double opacity = 0.3,
    int fontSize = 40,
    String color = '#FF0000',
  }) async {
    final response = await _dio.post('/watermark', data: {
      'file_id': fileId,
      'text': text,
      'opacity': opacity,
      'font_size': fontSize,
      'color': color,
    });
    return response.data['success'] == true;
  }

  Future<bool> protectPdf(String fileId, String password) async {
    final response = await _dio.post('/protect', data: {
      'file_id': fileId,
      'password': password,
    });
    return response.data['success'] == true;
  }

  // ─── Download ────────────────────────────────────────────────────────────

  Future<File?> downloadPdf(String fileId, String savePath) async {
    await _dio.download('/download/$fileId', savePath);
    return File(savePath);
  }

  String getDownloadUrl(String fileId) => '$_baseUrl/download/$fileId';
}
