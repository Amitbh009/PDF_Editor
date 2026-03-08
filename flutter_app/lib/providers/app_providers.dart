import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../services/api_service.dart';

// ─── API Service ──────────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// ─── Recent Documents ─────────────────────────────────────────────────────────

class RecentDocsNotifier extends StateNotifier<List<PdfDocument>> {
  RecentDocsNotifier() : super([]);

  void addDocument(PdfDocument doc) {
    // Remove duplicate if exists
    state = [doc, ...state.where((d) => d.fileId != doc.fileId)];
    // Keep only last 20
    if (state.length > 20) state = state.sublist(0, 20);
  }

  void removeDocument(String fileId) {
    state = state.where((d) => d.fileId != fileId).toList();
  }

  void clear() => state = [];
}

final recentDocsProvider =
    StateNotifierProvider<RecentDocsNotifier, List<PdfDocument>>(
  (ref) => RecentDocsNotifier(),
);

// ─── Active Document ──────────────────────────────────────────────────────────

final activeDocumentProvider = StateProvider<PdfDocument?>((ref) => null);

// ─── Current Page ─────────────────────────────────────────────────────────────

final currentPageProvider = StateProvider<int>((ref) => 1);

// ─── Active Tool ─────────────────────────────────────────────────────────────

enum EditorTool {
  select,
  highlight,
  underline,
  strikethrough,
  text,
  draw,
  eraser,
}

final activeToolProvider = StateProvider<EditorTool>((ref) => EditorTool.select);

// ─── Tool Color ───────────────────────────────────────────────────────────────

final toolColorProvider = StateProvider<String>((ref) => '#FFFF00');

// ─── Upload State ─────────────────────────────────────────────────────────────

enum UploadStatus { idle, uploading, success, error }

class UploadState {
  final UploadStatus status;
  final String? errorMessage;
  final PdfDocument? document;

  const UploadState({
    required this.status,
    this.errorMessage,
    this.document,
  });
}

class UploadNotifier extends StateNotifier<UploadState> {
  final ApiService _api;
  final RecentDocsNotifier _recents;

  UploadNotifier(this._api, this._recents)
      : super(const UploadState(status: UploadStatus.idle));

  Future<PdfDocument?> uploadFile(File file) async {
    state = const UploadState(status: UploadStatus.uploading);
    try {
      final doc = await _api.uploadPdf(file);
      _recents.addDocument(doc);
      state = UploadState(status: UploadStatus.success, document: doc);
      return doc;
    } catch (e) {
      state = UploadState(
        status: UploadStatus.error,
        errorMessage: 'Upload failed: ${e.toString()}',
      );
      return null;
    }
  }

  void reset() => state = const UploadState(status: UploadStatus.idle);
}

final uploadProvider = StateNotifierProvider<UploadNotifier, UploadState>((ref) {
  return UploadNotifier(
    ref.read(apiServiceProvider),
    ref.read(recentDocsProvider.notifier),
  );
});

// ─── Page Image Cache ─────────────────────────────────────────────────────────

final pageImageProvider = FutureProvider.family<String, (String, int)>(
  (ref, params) async {
    final api = ref.read(apiServiceProvider);
    return api.getPageImage(params.$1, params.$2);
  },
);

// ─── Sidebar Visibility ────────────────────────────────────────────────────────

final sidebarVisibleProvider = StateProvider<bool>((ref) => true);

// ─── Zoom Level ───────────────────────────────────────────────────────────────

final zoomLevelProvider = StateProvider<double>((ref) => 1.0);
