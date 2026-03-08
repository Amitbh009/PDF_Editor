// watermark_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class WatermarkDialog extends ConsumerStatefulWidget {
  final PdfDocument document;
  const WatermarkDialog({super.key, required this.document});

  @override
  ConsumerState<WatermarkDialog> createState() => _WatermarkDialogState();
}

class _WatermarkDialogState extends ConsumerState<WatermarkDialog> {
  final _textController = TextEditingController(text: 'CONFIDENTIAL');
  String _color = '#FF0000';
  double _opacity = 0.3;
  int _fontSize = 40;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Watermark'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textController,
              decoration: const InputDecoration(
                labelText: 'Watermark text',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Opacity: ${(_opacity * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _opacity,
              min: 0.05, max: 0.8,
              onChanged: (v) => setState(() => _opacity = v),
              activeColor: AppColors.accent,
            ),
            const SizedBox(height: 8),
            Text('Font size: $_fontSize',
              style: Theme.of(context).textTheme.bodySmall),
            Slider(
              value: _fontSize.toDouble(),
              min: 20, max: 80,
              divisions: 12,
              onChanged: (v) => setState(() => _fontSize = v.round()),
              activeColor: AppColors.accent,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Color: '),
                const SizedBox(width: 8),
                ...['#FF0000', '#000000', '#0000FF', '#808080'].map((c) {
                  final color = Color(int.parse('FF${c.substring(1)}', radix: 16));
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == c ? Colors.black : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _apply,
          child: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Apply'),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    if (_textController.text.isEmpty) return;
    setState(() => _loading = true);
    final api = ref.read(apiServiceProvider);
    await api.addWatermark(
      widget.document.fileId,
      _textController.text,
      opacity: _opacity,
      fontSize: _fontSize,
      color: _color,
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watermark added successfully!')),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
