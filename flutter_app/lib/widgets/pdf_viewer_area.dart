import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class PdfViewerArea extends ConsumerWidget {
  final PdfDocument document;
  const PdfViewerArea({super.key, required this.document});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPage = ref.watch(currentPageProvider);
    final zoom = ref.watch(zoomLevelProvider);

    return Container(
      color: const Color(0xFFD0D0D0),
      child: InteractiveViewer(
        minScale: 0.3,
        maxScale: 5.0,
        child: Center(
          child: _PageWithTextOverlay(
            document: document,
            page: currentPage,
            zoom: zoom,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page with Word-like text overlay
// ─────────────────────────────────────────────────────────────────────────────

class _PageWithTextOverlay extends ConsumerStatefulWidget {
  final PdfDocument document;
  final int page;
  final double zoom;

  const _PageWithTextOverlay({
    required this.document, required this.page, required this.zoom,
  });

  @override
  ConsumerState<_PageWithTextOverlay> createState() => _PageWithTextOverlayState();
}

class _PageWithTextOverlayState extends ConsumerState<_PageWithTextOverlay> {
  // Page render data
  String? _imageB64;
  double _pdfWidth = 595;
  double _pdfHeight = 842;
  double _renderWidth = 892;
  double _renderHeight = 1263;
  bool _loading = true;
  String? _error;

  // Text blocks loaded for editing
  List<TextBlock> _textBlocks = [];
  bool _textBlocksLoaded = false;

  // Selection / annotation drag
  Offset? _dragStart;
  Offset? _dragEnd;

  // Inline edit state
  TextBlock? _editingBlock;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  @override
  void didUpdateWidget(_PageWithTextOverlay old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.document.fileId != widget.document.fileId) {
      _textBlocks = [];
      _textBlocksLoaded = false;
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPageImageFull(widget.document.fileId, widget.page, dpi: 150);
      setState(() {
        _imageB64 = data['image_base64'] as String;
        _pdfWidth = (data['pdf_width'] ?? 595).toDouble();
        _pdfHeight = (data['pdf_height'] ?? 842).toDouble();
        _renderWidth = (data['render_width'] ?? 892).toDouble();
        _renderHeight = (data['render_height'] ?? 1263).toDouble();
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadTextBlocks() async {
    if (_textBlocksLoaded) return;
    try {
      final api = ref.read(apiServiceProvider);
      final blocks = await api.getPageTextBlocks(widget.document.fileId, widget.page);
      setState(() { _textBlocks = blocks; _textBlocksLoaded = true; });
    } catch (_) {}
  }

  // Scale factor: PDF coords → rendered pixel coords
  double get _scaleX => _renderWidth / _pdfWidth;
  double get _scaleY => _renderHeight / _pdfHeight;

  // Convert rendered pixel position → PDF coordinate
  Offset _toPdfCoords(Offset pixelPos) =>
      Offset(pixelPos.dx / _scaleX, pixelPos.dy / _scaleY);

  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingWidget();
    if (_error != null) return _errorWidget(_error!);
    return _buildPage();
  }

  Widget _buildPage() {
    final activeTool = ref.watch(activeToolProvider);

    return Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 20, offset: const Offset(0, 4))
        ],
      ),
      child: GestureDetector(
        onTapDown: (d) => _onTap(d.localPosition, activeTool),
        onPanStart: (d) {
          if (activeTool != EditorTool.select && activeTool != EditorTool.editText) {
            setState(() { _dragStart = d.localPosition; _dragEnd = d.localPosition; });
          }
        },
        onPanUpdate: (d) {
          if (_dragStart != null) setState(() => _dragEnd = d.localPosition);
        },
        onPanEnd: (_) => _onDragEnd(activeTool),
        child: Stack(
          children: [
            // ── PDF page image ──
            Image.memory(
              base64Decode(_imageB64!),
              fit: BoxFit.contain,
              width: _renderWidth,
              height: _renderHeight,
            ),

            // ── Text block overlays (edit mode) ──
            if (activeTool == EditorTool.editText)
              ..._textBlocks.map((block) => _buildTextBlockOverlay(block)),

            // ── Selection rectangle for annotations ──
            if (_dragStart != null && _dragEnd != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _SelectionPainter(
                    start: _dragStart!, end: _dragEnd!, tool: activeTool,
                  ),
                ),
              ),

            // ── Cursor hint for insert text ──
            if (activeTool == EditorTool.insertText)
              Positioned.fill(
                child: Container(
                  color: Colors.blue.withOpacity(0.04),
                  child: const Center(
                    child: Text(
                      'Tap anywhere to insert text',
                      style: TextStyle(color: Colors.blue, fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Text block overlay: shows a transparent hover box over each text span ──
  Widget _buildTextBlockOverlay(TextBlock block) {
    final left = block.x0 * _scaleX;
    final top = block.y0 * _scaleY;
    final w = block.width * _scaleX;
    final h = (block.height * _scaleY).clamp(14.0, 200.0);
    final isEditing = _editingBlock?.text == block.text &&
        _editingBlock?.x0 == block.x0 && _editingBlock?.y0 == block.y0;

    return Positioned(
      left: left, top: top, width: w.clamp(20.0, 600.0), height: h,
      child: GestureDetector(
        onTap: () => _startInlineEdit(block),
        child: Container(
          decoration: BoxDecoration(
            color: isEditing ? Colors.blue.withOpacity(0.15) : Colors.transparent,
            border: Border.all(
              color: isEditing ? Colors.blue : Colors.transparent,
              width: isEditing ? 1.5 : 0,
            ),
          ),
          child: isEditing
              ? null
              : Tooltip(
                  message: 'Click to edit: "${block.text}"',
                  child: Container(color: Colors.transparent),
                ),
        ),
      ),
    );
  }

  void _onTap(Offset pixelPos, EditorTool tool) {
    if (tool == EditorTool.editText) {
      // Check if tapped on a text block
      _loadTextBlocks();
      final pdfPos = _toPdfCoords(pixelPos);
      TextBlock? hit;
      for (final b in _textBlocks) {
        if (pdfPos.dx >= b.x0 && pdfPos.dx <= b.x1 &&
            pdfPos.dy >= b.y0 && pdfPos.dy <= b.y1) {
          hit = b;
          break;
        }
      }
      if (hit != null) {
        _startInlineEdit(hit);
      } else {
        // Tapped on empty space — show insert dialog
        _showInsertTextDialog(pdfPos);
      }
    } else if (tool == EditorTool.insertText) {
      _showInsertTextDialog(_toPdfCoords(pixelPos));
    } else if (tool == EditorTool.text) {
      _showAnnotationTextDialog(_toPdfCoords(pixelPos));
    }
  }

  // ── Word-like inline edit dialog ──────────────────────────────────────────
  void _startInlineEdit(TextBlock block) async {
    setState(() => _editingBlock = block);

    final controller = TextEditingController(text: block.text);
    double fontSize = block.size;
    bool bold = block.isBold;
    bool italic = block.isItalic;
    String fontColor = '#000000';
    String selectedFont = 'helv';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit_document, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text('Edit Text', style: TextStyle(fontSize: 16)),
              const Spacer(),
              // Font family selector
              DropdownButton<String>(
                value: selectedFont,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'helv', child: Text('Helvetica')),
                  DropdownMenuItem(value: 'timr', child: Text('Times')),
                  DropdownMenuItem(value: 'cour', child: Text('Courier')),
                ],
                onChanged: (v) => setDlg(() => selectedFont = v!),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Formatting toolbar ──
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      // Font size
                      const Text('Size:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 50,
                        child: TextFormField(
                          initialValue: fontSize.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => fontSize = double.tryParse(v) ?? fontSize,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Bold
                      _fmtBtn('B', bold, () => setDlg(() => bold = !bold),
                          const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 4),
                      // Italic
                      _fmtBtn('I', italic, () => setDlg(() => italic = !italic),
                          const TextStyle(fontStyle: FontStyle.italic, fontSize: 14)),
                      const SizedBox(width: 8),
                      // Color picker (simple presets)
                      const Text('Color:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      ...[
                        ('#000000', Colors.black), ('#CC0000', Colors.red),
                        ('#0000CC', Colors.blue), ('#006600', Colors.green),
                      ].map((pair) => GestureDetector(
                        onTap: () => setDlg(() => fontColor = pair.$1),
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: pair.$2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: fontColor == pair.$1 ? Colors.orange : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Text editor ──
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 6,
                  style: TextStyle(
                    fontSize: (fontSize * 0.9).clamp(8, 24),
                    fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Edit text...',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.yellow.shade50,
                    helperText: 'Original: "${block.text}"',
                    helperStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(ctx); setState(() => _editingBlock = null); },
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, {'delete': true}),
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              label: const Text('Delete Text', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, {
                'text': controller.text,
                'font_name': selectedFont,
                'font_size': fontSize,
                'font_color': fontColor,
                'bold': bold,
                'italic': italic,
              }),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Apply'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            ),
          ],
        ),
      ),
    );

    setState(() => _editingBlock = null);

    if (result == null) return;

    final api = ref.read(apiServiceProvider);

    if (result['delete'] == true) {
      // Redact the region
      await api.deleteRegion(
        fileId: widget.document.fileId,
        pageNumber: widget.page,
        x0: block.x0, y0: block.y0, x1: block.x1, y1: block.y1,
      );
    } else {
      final newText = result['text'] as String;
      if (newText == block.text) return; // no change

      await api.editTextInline(
        fileId: widget.document.fileId,
        pageNumber: widget.page,
        searchText: block.text,
        replacementText: newText,
        regionX0: block.x0 - 2, regionY0: block.y0 - 2,
        regionX1: block.x1 + 2, regionY1: block.y1 + 2,
        fontName: result['font_name'] as String?,
        fontSize: result['font_size'] as double?,
        fontColor: result['font_color'] as String?,
        bold: result['bold'] as bool?,
        italic: result['italic'] as bool?,
      );
    }

    // Reload page image to show changes
    setState(() {
      _textBlocksLoaded = false;
      _textBlocks = [];
    });
    await _loadPage();
    await _loadTextBlocks();
  }

  // ── Insert new text dialog ──────────────────────────────────────────────
  Future<void> _showInsertTextDialog(Offset pdfPos) async {
    final controller = TextEditingController();
    double fontSize = 12;
    bool bold = false;
    bool italic = false;
    String fontColor = '#000000';
    String fontName = 'helv';
    String align = 'left';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.text_fields, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              const Text('Insert Text', style: TextStyle(fontSize: 16)),
              const Spacer(),
              DropdownButton<String>(
                value: fontName,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'helv', child: Text('Helvetica')),
                  DropdownMenuItem(value: 'timr', child: Text('Times')),
                  DropdownMenuItem(value: 'cour', child: Text('Courier')),
                ],
                onChanged: (v) => setDlg(() => fontName = v!),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Formatting bar
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Text('Size:', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 50,
                        child: TextFormField(
                          initialValue: '12',
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4), border: OutlineInputBorder()),
                          onChanged: (v) => fontSize = double.tryParse(v) ?? fontSize,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _fmtBtn('B', bold, () => setDlg(() => bold = !bold), const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 4),
                      _fmtBtn('I', italic, () => setDlg(() => italic = !italic), const TextStyle(fontStyle: FontStyle.italic, fontSize: 14)),
                      const SizedBox(width: 8),
                      // Align
                      ...[('L', 'left'), ('C', 'center'), ('R', 'right')].map((a) =>
                        GestureDetector(
                          onTap: () => setDlg(() => align = a.$2),
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: align == a.$2 ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: align == a.$2 ? AppColors.accent : Colors.grey.shade300),
                            ),
                            child: Text(a.$1, style: const TextStyle(fontSize: 12)),
                          ),
                        )),
                      const SizedBox(width: 4),
                      ...[('#000000', Colors.black), ('#CC0000', Colors.red), ('#0000CC', Colors.blue), ('#006600', Colors.green)].map((pair) =>
                        GestureDetector(
                          onTap: () => setDlg(() => fontColor = pair.$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: pair.$2, shape: BoxShape.circle,
                              border: Border.all(color: fontColor == pair.$1 ? Colors.orange : Colors.transparent, width: 2),
                            ),
                          ),
                        )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Type your text here...',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, {
                'text': controller.text,
                'font_name': fontName, 'font_size': fontSize,
                'font_color': fontColor, 'bold': bold, 'italic': italic, 'align': align,
              }),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Insert'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            ),
          ],
        ),
      ),
    );

    if (result == null || (result['text'] as String).isEmpty) return;

    final api = ref.read(apiServiceProvider);
    await api.insertTextBlock(
      fileId: widget.document.fileId,
      pageNumber: widget.page,
      text: result['text'] as String,
      x: pdfPos.dx, y: pdfPos.dy,
      width: 300, height: 200,
      fontName: result['font_name'] as String,
      fontSize: result['font_size'] as double,
      fontColor: result['font_color'] as String,
      bold: result['bold'] as bool,
      italic: result['italic'] as bool,
      align: result['align'] as String,
    );

    setState(() { _textBlocksLoaded = false; _textBlocks = []; });
    await _loadPage();
  }

  // ── Old-style annotation text ──────────────────────────────────────────
  Future<void> _showAnnotationTextDialog(Offset pdfPos) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(controller: controller, maxLines: 3, autofocus: true,
          decoration: const InputDecoration(hintText: 'Type note...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final api = ref.read(apiServiceProvider);
    await api.addAnnotation(
      fileId: widget.document.fileId, page: widget.page,
      type: 'freetext', content: result,
      x: pdfPos.dx, y: pdfPos.dy, width: 160, height: 40,
    );
    await _loadPage();
  }

  // ── Drag annotation finish ──────────────────────────────────────────────
  Future<void> _onDragEnd(EditorTool tool) async {
    if (_dragStart == null || _dragEnd == null) return;
    final rect = Rect.fromPoints(_dragStart!, _dragEnd!);
    setState(() { _dragStart = null; _dragEnd = null; });
    if (rect.width < 5 || rect.height < 5) return;

    final typeMap = {
      EditorTool.highlight: 'highlight',
      EditorTool.underline: 'underline',
      EditorTool.strikethrough: 'strikethrough',
    };
    final annType = typeMap[tool];
    if (annType == null) return;

    final pdfStart = _toPdfCoords(rect.topLeft);
    final pdfEnd = _toPdfCoords(rect.bottomRight);
    final api = ref.read(apiServiceProvider);
    await api.addAnnotation(
      fileId: widget.document.fileId, page: widget.page,
      type: annType,
      x: pdfStart.dx, y: pdfStart.dy,
      width: pdfEnd.dx - pdfStart.dx, height: pdfEnd.dy - pdfStart.dy,
    );
    await _loadPage();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _fmtBtn(String label, bool active, VoidCallback onTap, TextStyle style) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? AppColors.accent : Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Text(label, style: style),
      ),
    );
  }

  Widget _loadingWidget() => Container(
    width: 595, height: 842, color: Colors.white,
    child: const Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.accent),
        SizedBox(height: 12),
        Text('Loading page...', style: TextStyle(color: AppColors.accent)),
      ],
    )),
  );

  Widget _errorWidget(String err) => Container(
    width: 595, height: 400, color: Colors.white,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.wifi_off_rounded, color: Colors.red.shade400, size: 48),
      const SizedBox(height: 12),
      const Text('Could not load page', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Make sure backend is running on port 8000',
        style: TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(err, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        onPressed: _loadPage,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Retry'),
      ),
    ]),
  );
}

// ─── Selection painter ────────────────────────────────────────────────────────

class _SelectionPainter extends CustomPainter {
  final Offset start, end;
  final EditorTool tool;

  const _SelectionPainter({required this.start, required this.end, required this.tool});

  @override
  void paint(Canvas canvas, Size size) {
    final colorMap = {
      EditorTool.highlight: Colors.yellow,
      EditorTool.underline: Colors.green,
      EditorTool.strikethrough: Colors.red,
      EditorTool.draw: Colors.blue,
    };
    final color = colorMap[tool] ?? AppColors.accent;
    final rect = Rect.fromPoints(start, end);
    canvas.drawRect(rect, Paint()..color = color.withOpacity(0.25)..style = PaintingStyle.fill);
    canvas.drawRect(rect, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}