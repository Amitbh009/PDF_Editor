class PdfDocument {
  final String fileId;
  final String filename;
  final int pageCount;
  final String? title;
  final String? author;
  final int sizeBytes;
  final DateTime openedAt;
  final String? localPath;

  const PdfDocument({
    required this.fileId,
    required this.filename,
    required this.pageCount,
    this.title,
    this.author,
    required this.sizeBytes,
    required this.openedAt,
    this.localPath,
  });

  String get displayName => (title != null && title!.isNotEmpty) ? title! : filename;

  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  factory PdfDocument.fromJson(Map<String, dynamic> json) {
    return PdfDocument(
      fileId: json['file_id'] as String,
      filename: json['filename'] as String,
      pageCount: json['page_count'] as int? ?? 0,
      title: json['title'] as String?,
      author: json['author'] as String?,
      sizeBytes: json['size_bytes'] as int? ?? 0,
      openedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'file_id': fileId,
    'filename': filename,
    'page_count': pageCount,
    'title': title,
    'author': author,
    'size_bytes': sizeBytes,
    'opened_at': openedAt.toIso8601String(),
    'local_path': localPath,
  };

  PdfDocument copyWith({String? localPath}) {
    return PdfDocument(
      fileId: fileId,
      filename: filename,
      pageCount: pageCount,
      title: title,
      author: author,
      sizeBytes: sizeBytes,
      openedAt: openedAt,
      localPath: localPath ?? this.localPath,
    );
  }
}

enum AnnotationType {
  highlight,
  underline,
  strikethrough,
  text,
  freeText,
  draw,
}

class PdfAnnotation {
  final String id;
  final AnnotationType type;
  final int page;
  final double x, y, width, height;
  final String? content;
  final String color;
  final DateTime createdAt;

  const PdfAnnotation({
    required this.id,
    required this.type,
    required this.page,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.content,
    required this.color,
    required this.createdAt,
  });
}
