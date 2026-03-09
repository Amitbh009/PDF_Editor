import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class FindReplaceDialog extends ConsumerStatefulWidget {
  final PdfDocument document;
  final VoidCallback? onDone;

  const FindReplaceDialog({super.key, required this.document, this.onDone});

  @override
  ConsumerState<FindReplaceDialog> createState() => _FindReplaceDialogState();
}

class _FindReplaceDialogState extends ConsumerState<FindReplaceDialog> {
  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  bool _caseSensitive = false;
  bool _allPages = true;
  bool _loading = false;
  String? _result;

  @override
  void dispose() {
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    super.dispose();
  }

  Future<void> _doReplace() async {
    if (_findCtrl.text.isEmpty) return;
    setState(() { _loading = true; _result = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final count = await api.findAndReplace(
        fileId: widget.document.fileId,
        findText: _findCtrl.text,
        replaceText: _replaceCtrl.text,
        caseSensitive: _caseSensitive,
        allPages: _allPages,
      );
      setState(() {
        _loading = false;
        _result = count > 0
            ? 'Replaced $count occurrence${count > 1 ? 's' : ''} ✓'
            : 'No matches found for "${_findCtrl.text}"';
      });
      if (count > 0) widget.onDone?.call();
    } catch (e) {
      setState(() { _loading = false; _result = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.find_replace_rounded, color: AppColors.accent, size: 20),
        const SizedBox(width: 8),
        const Text('Find & Replace', style: TextStyle(fontSize: 16)),
      ]),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Find field
            const Text('Find:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _findCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Text to find...',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onSubmitted: (_) => _doReplace(),
            ),
            const SizedBox(height: 12),
            // Replace field
            const Text('Replace with:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _replaceCtrl,
              decoration: const InputDecoration(
                hintText: 'Replacement text (leave empty to delete)...',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.edit, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            // Options
            Row(
              children: [
                Checkbox(
                  value: _caseSensitive,
                  onChanged: (v) => setState(() => _caseSensitive = v!),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('Case sensitive', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 16),
                Checkbox(
                  value: _allPages,
                  onChanged: (v) => setState(() => _allPages = v!),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const Text('All pages', style: TextStyle(fontSize: 13)),
              ],
            ),
            // Result message
            if (_result != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _result!.contains('Error') || _result!.contains('No matches')
                      ? Colors.orange.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _result!.contains('Error') || _result!.contains('No matches')
                        ? Colors.orange.shade300 : Colors.green.shade300,
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _result!.contains('✓') ? Icons.check_circle_outline : Icons.info_outline,
                    size: 16,
                    color: _result!.contains('✓') ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_result!, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ElevatedButton.icon(
          onPressed: _loading ? null : _doReplace,
          icon: _loading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.find_replace_rounded, size: 16),
          label: const Text('Replace All'),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
        ),
      ],
    );
  }
}