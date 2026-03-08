import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class PdfViewerArea extends ConsumerWidget {
  final PdfDocument document;
  const PdfViewerArea({super.key, required this.document});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPage = ref.watch(currentPageProvider);
    final zoom = ref.watch(zoomLevelProvider);
    final activeTool = ref.watch(activeToolProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E6E0),
      child: InteractiveViewer(
        minScale: 0.3,
        maxScale: 5.0,
        child: Center(
          child: _PageView(
            document: document,
            page: currentPage,
            zoom: zoom,
            activeTool: activeTool,
          ),
        ),
      ),
    );
  }
}

class _PageView extends ConsumerStatefulWidget {
  final PdfDocument document;
  final int page;
  final double zoom;
  final EditorTool activeTool;

  const _PageView({
    required this.document,
    required this.page,
    required this.zoom,
    required this.activeTool,
  });

  @override
  ConsumerState<_PageView> createState() => _PageViewState();
}

class _PageViewState extends ConsumerState<_PageView> {
  Offset? _annotationStart;
  Offset? _annotationEnd;
  final List<_AnnotationOverlay> _pendingAnnotations = [];

  @override
  Widget build(BuildContext context) {
    final pageImageAsync = ref.watch(
      pageImageProvider((widget.document.fileId, widget.page)),
    );

    return pageImageAsync.when(
      loading: () => _buildLoadingPage(),
      error: (err, _) => _buildErrorPage(err.toString()),
      data: (imageB64) => _buildPage(imageB64),
    );
  }

  Widget _buildPage(String imageB64) {
    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: GestureDetector(
        onTapDown: (details) => _handleTap(details.localPosition),
        onPanStart: (details) {
          setState(() => _annotationStart = details.localPosition);
        },
        onPanUpdate: (details) {
          setState(() => _annotationEnd = details.localPosition);
        },
        onPanEnd: (_) => _confirmAnnotation(),
        child: Stack(
          children: [
            // PDF page rendered as image
            Image.memory(
              base64Decode(imageB64),
              fit: BoxFit.contain,
            ),

            // Draw current selection rectangle
            if (_annotationStart != null && _annotationEnd != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SelectionPainter(
                    start: _annotationStart!,
                    end: _annotationEnd!,
                    tool: widget.activeTool,
                  ),
                ),
              ),

            // Show applied annotations
            ..._pendingAnnotations.map((ann) => Positioned(
              left: ann.rect.left,
              top: ann.rect.top,
              width: ann.rect.width,
              height: ann.rect.height,
              child: ann.widget,
            )),
          ],
        ),
      ),
    );
  }

  void _handleTap(Offset position) {
    if (widget.activeTool == EditorTool.text) {
      _showTextAnnotationDialog(position);
    }
  }

  Future<void> _showTextAnnotationDialog(Offset position) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Text Note'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Type your note...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final api = ref.read(apiServiceProvider);
      await api.addAnnotation(
        fileId: widget.document.fileId,
        page: widget.page,
        type: 'freetext',
        content: result,
        x: position.dx,
        y: position.dy,
        width: 160,
        height: 40,
      );
      if (mounted) {
        setState(() {
          _pendingAnnotations.add(_AnnotationOverlay(
            rect: Rect.fromLTWH(position.dx, position.dy, 160, 40),
            widget: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.yellow.shade100,
                border: Border.all(color: Colors.amber),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(result, style: const TextStyle(fontSize: 11)),
            ),
          ));
        });
      }
    }
  }

  Future<void> _confirmAnnotation() async {
    if (_annotationStart == null || _annotationEnd == null) return;

    final start = _annotationStart!;
    final end = _annotationEnd!;
    final rect = Rect.fromPoints(start, end);

    if (rect.width < 5 || rect.height < 5) {
      setState(() { _annotationStart = null; _annotationEnd = null; });
      return;
    }

    final tool = widget.activeTool;
    if (tool == EditorTool.select) {
      setState(() { _annotationStart = null; _annotationEnd = null; });
      return;
    }

    final typeMap = {
      EditorTool.highlight: 'highlight',
      EditorTool.underline: 'underline',
      EditorTool.strikethrough: 'strikethrough',
    };

    final annType = typeMap[tool];
    if (annType != null) {
      final api = ref.read(apiServiceProvider);
      final colorMap = {
        EditorTool.highlight: '#FFFF00',
        EditorTool.underline: '#06D6A0',
        EditorTool.strikethrough: '#EF476F',
      };
      await api.addAnnotation(
        fileId: widget.document.fileId,
        page: widget.page,
        type: annType,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
        color: colorMap[tool] ?? '#FFFF00',
      );

      final colorWidget = {
        EditorTool.highlight: Colors.yellow.withOpacity(0.4),
        EditorTool.underline: Colors.green.withOpacity(0.4),
        EditorTool.strikethrough: Colors.red.withOpacity(0.4),
      }[tool]!;

      setState(() {
        _pendingAnnotations.add(_AnnotationOverlay(
          rect: rect,
          widget: Container(color: colorWidget),
        ));
        _annotationStart = null;
        _annotationEnd = null;
      });
    }
  }

  Widget _buildLoadingPage() {
    return Container(
      width: 595,
      height: 842,
      margin: const EdgeInsets.all(20),
      color: Colors.white,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.accent),
            SizedBox(height: 16),
            Text('Loading page...', style: TextStyle(color: AppColors.accent)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorPage(String error) {
    return Container(
      width: 595,
      height: 400,
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.red.shade400, size: 48),
          const SizedBox(height: 16),
          Text(
            'Could not load page',
            style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure the backend is running on port 8000',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            error,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AnnotationOverlay {
  final Rect rect;
  final Widget widget;
  _AnnotationOverlay({required this.rect, required this.widget});
}

class _SelectionPainter extends CustomPainter {
  final Offset start;
  final Offset end;
  final EditorTool tool;

  const _SelectionPainter({
    required this.start,
    required this.end,
    required this.tool,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final colorMap = {
      EditorTool.highlight: AppColors.toolHighlight,
      EditorTool.underline: AppColors.toolUnderline,
      EditorTool.strikethrough: AppColors.toolStrike,
      EditorTool.draw: AppColors.toolDraw,
    };
    final color = colorMap[tool] ?? AppColors.accent;
    final rect = Rect.fromPoints(start, end);

    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
