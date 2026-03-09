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
        minScale: 0.3, maxScale: 5.0,
        child: Center(
          child: _PageCanvas(document: document, page: currentPage, zoom: zoom),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page canvas — handles render + OCR overlay + all editing interactions
// ─────────────────────────────────────────────────────────────────────────────

class _PageCanvas extends ConsumerStatefulWidget {
  final PdfDocument document;
  final int page;
  final double zoom;
  const _PageCanvas({required this.document, required this.page, required this.zoom});

  @override
  ConsumerState<_PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends ConsumerState<_PageCanvas> {
  // Render state
  String? _imageB64;
  double _pdfW = 595, _pdfH = 842;
  double _renderW = 892, _renderH = 1263;
  bool _loading = true;
  String? _error;

  // OCR state
  List<TextBlock> _words = [];
  bool _ocrDone = false;
  bool _ocrRunning = false;

  // Interaction state
  Offset? _dragStart, _dragEnd;
  TextBlock? _editingBlock;

  @override
  void initState() { super.initState(); _loadPage(); }

  @override
  void didUpdateWidget(_PageCanvas old) {
    super.didUpdateWidget(old);
    if (old.page != widget.page || old.document.fileId != widget.document.fileId) {
      _words = []; _ocrDone = false;
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getPageImageFull(widget.document.fileId, widget.page);
      setState(() {
        _imageB64  = data['image_base64'] as String;
        _pdfW      = (data['pdf_width']    ?? 595).toDouble();
        _pdfH      = (data['pdf_height']   ?? 842).toDouble();
        _renderW   = (data['render_width'] ?? 892).toDouble();
        _renderH   = (data['render_height']?? 1263).toDouble();
        _loading   = false;
      });
      // Load existing text blocks (works if PDF already has text layer)
      await _tryLoadTextBlocks();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _tryLoadTextBlocks() async {
    try {
      final api = ref.read(apiServiceProvider);
      final blocks = await api.getPageTextBlocks(widget.document.fileId, widget.page);
      if (blocks.isNotEmpty) {
        setState(() { _words = blocks; _ocrDone = true; });
      }
    } catch (_) {}
  }

  Future<void> _runOCR() async {
    setState(() { _ocrRunning = true; });
    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.runOcr(widget.document.fileId);
      final pageData = result['pages'] as Map<String, dynamic>? ?? {};
      final rawWords = pageData[widget.page.toString()] as List? ??
                       pageData[widget.page] as List? ?? [];
      setState(() {
        _words = rawWords
            .map((w) => TextBlock.fromJson(Map<String, dynamic>.from(w)))
            .toList();
        _ocrDone    = true;
        _ocrRunning = false;
      });
    } catch (e) {
      setState(() { _ocrRunning = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Scale helpers ──
  double get _sx => _renderW / _pdfW;
  double get _sy => _renderH / _pdfH;
  Offset _toPdf(Offset px) => Offset(px.dx / _sx, px.dy / _sy);

  @override
  Widget build(BuildContext context) {
    if (_loading) return _shimmer();
    if (_error != null) return _errorView();
    return _buildCanvas();
  }

  Widget _buildCanvas() {
    final tool = ref.watch(activeToolProvider);

    return Stack(
      children: [
        // ── Page card ──
        Container(
          margin: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: GestureDetector(
            onTapDown: (d) => _onTap(d.localPosition, tool),
            onPanStart: (d) {
              if (_isDragTool(tool)) setState(() { _dragStart = d.localPosition; _dragEnd = d.localPosition; });
            },
            onPanUpdate: (d) { if (_dragStart != null) setState(() => _dragEnd = d.localPosition); },
            onPanEnd: (_) => _onDragEnd(tool),
            child: Stack(children: [
              // PDF image
              Image.memory(base64Decode(_imageB64!), fit: BoxFit.contain, width: _renderW, height: _renderH),

              // Edit-text overlays
              if (tool == EditorTool.editText && _ocrDone)
                ..._words.map(_wordOverlay),

              // Insert-text hint
              if (tool == EditorTool.insertText)
                Positioned.fill(child: Container(
                  color: Colors.blue.withOpacity(0.03),
                  child: const Align(alignment: Alignment.topCenter,
                    child: Padding(padding: EdgeInsets.only(top: 8),
                      child: Text('Tap anywhere to insert text',
                        style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.w500)))),
                )),

              // Drag selection rect
              if (_dragStart != null && _dragEnd != null)
                Positioned.fill(child: CustomPaint(
                  painter: _SelPainter(start: _dragStart!, end: _dragEnd!, tool: tool))),
            ]),
          ),
        ),

        // ── OCR banner (shown when Edit Text is active but OCR not done) ──
        if (tool == EditorTool.editText && !_ocrDone)
          Positioned(
            left: 24, right: 24, top: 24,
            child: _OcrBanner(running: _ocrRunning, onRun: _runOCR),
          ),
      ],
    );
  }

  Widget _wordOverlay(TextBlock block) {
    final left = block.x0 * _sx;
    final top  = block.y0 * _sy;
    final w    = (block.width  * _sx).clamp(10.0, 800.0);
    final h    = (block.height * _sy).clamp(8.0,  120.0);
    final isEditing = identical(_editingBlock, block);

    return Positioned(
      left: left, top: top, width: w, height: h,
      child: GestureDetector(
        onTap: () => _startInlineEdit(block),
        child: Tooltip(
          message: '"${block.text}"  — tap to edit',
          child: Container(
            decoration: BoxDecoration(
              color: isEditing ? Colors.blue.withOpacity(0.18) : Colors.yellow.withOpacity(0.01),
              border: Border.all(
                color: isEditing ? Colors.blue : Colors.blue.withOpacity(0.25),
                width: isEditing ? 1.5 : 0.8,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  // ── Edit dialog ──────────────────────────────────────────────────────────
  void _startInlineEdit(TextBlock block) async {
    setState(() => _editingBlock = block);
    final ctrl   = TextEditingController(text: block.text);
    double fSize = block.size.clamp(6.0, 48.0);
    bool bold = false, italic = false;
    String color = '#000000', fontName = 'helv';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.edit_document, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Edit Text', style: TextStyle(fontSize: 16))),
          // Font dropdown
          DropdownButton<String>(
            value: fontName, isDense: true,
            items: const [
              DropdownMenuItem(value: 'helv',  child: Text('Helvetica', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'timr',  child: Text('Times',     style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'cour',  child: Text('Courier',   style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setD(() => fontName = v!),
          ),
        ]),
        content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Formatting bar
          _FormatBar(
            fontSize: fSize, bold: bold, italic: italic, color: color,
            onSizeChange: (v) => setD(() => fSize = v),
            onBold:  () => setD(() => bold  = !bold),
            onItalic:() => setD(() => italic= !italic),
            onColor: (v) => setD(() => color= v),
          ),
          const SizedBox(height: 12),
          // Text field
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 6,
            style: TextStyle(
              fontSize: (fSize * 0.85).clamp(8, 22).toDouble(),
              fontWeight: bold   ? FontWeight.bold : FontWeight.normal,
              fontStyle:  italic ? FontStyle.italic : FontStyle.normal,
            ),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              filled: true, fillColor: Colors.yellow.shade50,
              helperText: 'Original: "${block.text}"',
              helperStyle: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ])),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); setState(() => _editingBlock = null); },
            child: const Text('Cancel')),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, {'delete': true}),
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            label: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, {
              'text': ctrl.text, 'font_name': fontName, 'font_size': fSize,
              'font_color': color, 'bold': bold, 'italic': italic,
            }),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Apply'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      )),
    );

    setState(() => _editingBlock = null);
    if (result == null) return;
    final api = ref.read(apiServiceProvider);

    if (result['delete'] == true) {
      await api.deleteRegion(
        fileId: widget.document.fileId, pageNumber: widget.page,
        x0: block.x0 - 1, y0: block.y0 - 1,
        x1: block.x1 + 1, y1: block.y1 + 1,
      );
    } else {
      final newText = result['text'] as String;
      if (newText == block.text) return;
      await api.editTextInline(
        fileId: widget.document.fileId, pageNumber: widget.page,
        searchText: block.text, replacementText: newText,
        regionX0: block.x0 - 2, regionY0: block.y0 - 2,
        regionX1: block.x1 + 2, regionY1: block.y1 + 2,
        fontName:  result['font_name']  as String?,
        fontSize:  result['font_size']  as double?,
        fontColor: result['font_color'] as String?,
        bold:      result['bold']       as bool?,
        italic:    result['italic']     as bool?,
      );
    }
    // Reload
    setState(() { _words = []; _ocrDone = false; });
    await _loadPage();
  }

  // ── Insert text dialog ──────────────────────────────────────────────────
  void _onTap(Offset px, EditorTool tool) {
    if (tool == EditorTool.editText) {
      final pdf = _toPdf(px);
      // Find closest word
      TextBlock? hit;
      double best = double.infinity;
      for (final b in _words) {
        if (pdf.dx >= b.x0 - 2 && pdf.dx <= b.x1 + 2 &&
            pdf.dy >= b.y0 - 2 && pdf.dy <= b.y1 + 2) {
          final d = (Offset((b.x0+b.x1)/2,(b.y0+b.y1)/2) - pdf).distance;
          if (d < best) { best = d; hit = b; }
        }
      }
      if (hit != null) _startInlineEdit(hit);
      else             _showInsertDialog(_toPdf(px));
    } else if (tool == EditorTool.insertText) {
      _showInsertDialog(_toPdf(px));
    } else if (tool == EditorTool.text) {
      _showNoteDialog(_toPdf(px));
    }
  }

  Future<void> _showInsertDialog(Offset pdfPos) async {
    final ctrl = TextEditingController();
    double fSize = 12; bool bold = false, italic = false;
    String color = '#000000', fontName = 'helv', align = 'left';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(children: [
          const Icon(Icons.text_fields_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Insert Text', style: TextStyle(fontSize: 16))),
          DropdownButton<String>(
            value: fontName, isDense: true,
            items: const [
              DropdownMenuItem(value: 'helv', child: Text('Helvetica', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'timr', child: Text('Times',     style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'cour', child: Text('Courier',   style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setD(() => fontName = v!),
          ),
        ]),
        content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
          _FormatBar(
            fontSize: fSize, bold: bold, italic: italic, color: color,
            onSizeChange: (v) => setD(() => fSize = v),
            onBold:  () => setD(() => bold  = !bold),
            onItalic:() => setD(() => italic= !italic),
            onColor: (v) => setD(() => color= v),
            showAlign: true, align: align,
            onAlign: (v) => setD(() => align = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl, autofocus: true, maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Type here...', border: OutlineInputBorder(), filled: true),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, {
              'text': ctrl.text, 'font_name': fontName, 'font_size': fSize,
              'font_color': color, 'bold': bold, 'italic': italic, 'align': align,
            }),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Insert'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      )),
    );

    if (result == null || (result['text'] as String).isEmpty) return;
    final api = ref.read(apiServiceProvider);
    await api.insertTextBlock(
      fileId: widget.document.fileId, pageNumber: widget.page,
      text: result['text'] as String,
      x: pdfPos.dx, y: pdfPos.dy, width: 300, height: 200,
      fontName:  result['font_name']  as String,
      fontSize:  result['font_size']  as double,
      fontColor: result['font_color'] as String,
      bold:   result['bold']   as bool,
      italic: result['italic'] as bool,
      align:  result['align']  as String,
    );
    await _loadPage();
  }

  Future<void> _showNoteDialog(Offset pdfPos) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3,
          decoration: const InputDecoration(hintText: 'Type note...', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    final api = ref.read(apiServiceProvider);
    await api.addAnnotation(
      fileId: widget.document.fileId, page: widget.page,
      type: 'freetext', content: text,
      x: pdfPos.dx, y: pdfPos.dy, width: 160, height: 40,
    );
    await _loadPage();
  }

  bool _isDragTool(EditorTool t) =>
      t == EditorTool.highlight || t == EditorTool.underline || t == EditorTool.strikethrough;

  Future<void> _onDragEnd(EditorTool tool) async {
    if (_dragStart == null || _dragEnd == null) return;
    final r = Rect.fromPoints(_dragStart!, _dragEnd!);
    setState(() { _dragStart = null; _dragEnd = null; });
    if (r.width < 5 || r.height < 5) return;
    final typeMap = {
      EditorTool.highlight: 'highlight',
      EditorTool.underline: 'underline',
      EditorTool.strikethrough: 'strikethrough',
    };
    final type = typeMap[tool]; if (type == null) return;
    final s = _toPdf(r.topLeft); final e = _toPdf(r.bottomRight);
    final api = ref.read(apiServiceProvider);
    await api.addAnnotation(
      fileId: widget.document.fileId, page: widget.page,
      type: type, x: s.dx, y: s.dy, width: e.dx - s.dx, height: e.dy - s.dy,
    );
    await _loadPage();
  }

  // ── Loading / error widgets ──────────────────────────────────────────────

  Widget _shimmer() => Container(
    width: 595, height: 842, color: Colors.white,
    child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: AppColors.accent),
      SizedBox(height: 12),
      Text('Loading page...', style: TextStyle(color: AppColors.accent, fontSize: 13)),
    ])),
  );

  Widget _errorView() => Container(
    width: 595, height: 400, color: Colors.white,
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.wifi_off_rounded, color: Colors.red.shade400, size: 48),
      const SizedBox(height: 12),
      const Text('Could not load page', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Make sure backend is running on port 8000',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      Text(_error!, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: _loadPage,
        icon: const Icon(Icons.refresh, size: 16), label: const Text('Retry')),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// OCR Banner
// ─────────────────────────────────────────────────────────────────────────────

class _OcrBanner extends StatelessWidget {
  final bool running;
  final VoidCallback onRun;
  const _OcrBanner({required this.running, required this.onRun});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 12)],
        border: Border.all(color: AppColors.accent.withOpacity(0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.document_scanner_rounded, color: AppColors.accent, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('OCR Required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            running ? 'Running Tesseract OCR... this takes 5–20 seconds per page'
                    : 'This PDF has image-based text. Run OCR to enable click-to-edit.',
            style: const TextStyle(color: Color(0xFF8888AA), fontSize: 11),
          ),
        ])),
        const SizedBox(width: 12),
        running
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
            : ElevatedButton.icon(
                onPressed: onRun,
                icon: const Icon(Icons.scanner, size: 15),
                label: const Text('Run OCR', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                ),
              ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Formatting bar (shared between edit & insert dialogs)
// ─────────────────────────────────────────────────────────────────────────────

class _FormatBar extends StatelessWidget {
  final double fontSize;
  final bool bold, italic;
  final String color;
  final ValueChanged<double> onSizeChange;
  final VoidCallback onBold, onItalic;
  final ValueChanged<String> onColor;
  final bool showAlign;
  final String? align;
  final ValueChanged<String>? onAlign;

  const _FormatBar({
    required this.fontSize, required this.bold, required this.italic, required this.color,
    required this.onSizeChange, required this.onBold, required this.onItalic, required this.onColor,
    this.showAlign = false, this.align, this.onAlign,
  });

  static const _colors = [
    ('#000000', Color(0xFF000000)),
    ('#CC0000', Color(0xFFCC0000)),
    ('#0055CC', Color(0xFF0055CC)),
    ('#006600', Color(0xFF006600)),
    ('#7700AA', Color(0xFF7700AA)),
    ('#CC6600', Color(0xFFCC6600)),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        // Font size
        SizedBox(width: 52, child: TextFormField(
          initialValue: fontSize.toStringAsFixed(0),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true, labelText: 'pt',
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: OutlineInputBorder()),
          onChanged: (v) => onSizeChange(double.tryParse(v) ?? fontSize),
        )),

        // Bold
        _fmtBtn('B', bold, onBold, const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        // Italic
        _fmtBtn('I', italic, onItalic, const TextStyle(fontStyle: FontStyle.italic, fontSize: 14)),

        if (showAlign && onAlign != null) ...[
          const SizedBox(width: 4),
          ...(['L', 'C', 'R'].map((a) {
            final av = a == 'L' ? 'left' : a == 'C' ? 'center' : 'right';
            return _fmtBtn(a, align == av, () => onAlign!(av), const TextStyle(fontSize: 12));
          })),
        ],

        const SizedBox(width: 4),
        // Color swatches
        ..._colors.map((pair) => GestureDetector(
          onTap: () => onColor(pair.$1),
          child: Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: pair.$2, shape: BoxShape.circle,
              border: Border.all(
                color: color == pair.$1 ? Colors.orange : Colors.transparent, width: 2)),
          ),
        )),
      ]),
    );
  }

  Widget _fmtBtn(String lbl, bool active, VoidCallback onTap, TextStyle style) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: active ? AppColors.accent.withOpacity(0.2) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: active ? AppColors.accent : Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Text(lbl, style: style),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Selection painter
// ─────────────────────────────────────────────────────────────────────────────

class _SelPainter extends CustomPainter {
  final Offset start, end;
  final EditorTool tool;
  const _SelPainter({required this.start, required this.end, required this.tool});

  @override
  void paint(Canvas canvas, Size size) {
    final colors = {
      EditorTool.highlight:     Colors.yellow,
      EditorTool.underline:     Colors.green,
      EditorTool.strikethrough: Colors.red,
      EditorTool.draw:          Colors.blue,
    };
    final c = colors[tool] ?? AppColors.accent;
    final r = Rect.fromPoints(start, end);
    canvas.drawRect(r, Paint()..color = c.withOpacity(0.25)..style = PaintingStyle.fill);
    canvas.drawRect(r, Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}