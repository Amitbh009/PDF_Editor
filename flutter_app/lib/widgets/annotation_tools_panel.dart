// annotation_tools_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class AnnotationToolsPanel extends ConsumerWidget {
  final PdfDocument document;
  final VoidCallback onClose;
  const AnnotationToolsPanel({super.key, required this.document, required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          left: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Text('Annotations', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SectionLabel('Highlight Tools'),
                _ColorTile(label: 'Yellow', color: AppColors.toolHighlight, tool: EditorTool.highlight),
                _ColorTile(label: 'Green', color: AppColors.toolUnderline, tool: EditorTool.underline),
                _ColorTile(label: 'Red', color: AppColors.toolStrike, tool: EditorTool.strikethrough),
                const SizedBox(height: 16),
                _SectionLabel('Write & Draw'),
                _ColorTile(label: 'Text Note', color: AppColors.toolText, tool: EditorTool.text),
                _ColorTile(label: 'Freehand', color: AppColors.toolDraw, tool: EditorTool.draw),
                const SizedBox(height: 16),
                _SectionLabel('Color'),
                _ColorPicker(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: AppColors.accent, letterSpacing: 0.8,
    )),
  );
}

class _ColorTile extends ConsumerWidget {
  final String label;
  final Color color;
  final EditorTool tool;
  const _ColorTile({required this.label, required this.color, required this.tool});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeToolProvider) == tool;
    return GestureDetector(
      onTap: () => ref.read(activeToolProvider.notifier).state = tool,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          border: Border.all(color: active ? color : Colors.transparent),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

class _ColorPicker extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ['#FFFF00', '#06D6A0', '#EF476F', '#118AB2', '#9B5DE5', '#FF6B35', '#000000'];
    final current = ref.watch(toolColorProvider);
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: colors.map((hex) {
        final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
        final isSelected = current == hex;
        return GestureDetector(
          onTap: () => ref.read(toolColorProvider.notifier).state = hex,
          child: Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : Colors.transparent, width: 2,
              ),
              boxShadow: isSelected
                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}
