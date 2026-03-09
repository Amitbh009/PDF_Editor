import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'watermark_dialog.dart';
import 'password_dialog.dart';
import 'find_replace_dialog.dart';

class EditorToolbar extends ConsumerWidget {
  final PdfDocument document;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleAnnotations;
  final VoidCallback? onPageRefresh;

  const EditorToolbar({
    super.key,
    required this.document,
    required this.onToggleSidebar,
    required this.onToggleAnnotations,
    this.onPageRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTool = ref.watch(activeToolProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface2 : AppColors.lightSurface2,
        border: Border(bottom: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        )),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // ── Sidebar toggle ──
            _ToolbarIconBtn(icon: Icons.view_sidebar_outlined, tooltip: 'Toggle page panel', onPressed: onToggleSidebar),
            _Divider(),

            // ── Undo / Redo ──
            _ToolbarIconBtn(
              icon: Icons.undo_rounded, tooltip: 'Undo (Ctrl+Z)',
              onPressed: () async {
                final api = ref.read(apiServiceProvider);
                final ok = await api.undo(document.fileId);
                if (ok && context.mounted) {
                  onPageRefresh?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Undo'), duration: Duration(seconds: 1)));
                }
              },
            ),
            _ToolbarIconBtn(
              icon: Icons.redo_rounded, tooltip: 'Redo (Ctrl+Y)',
              onPressed: () async {
                final api = ref.read(apiServiceProvider);
                final ok = await api.redo(document.fileId);
                if (ok && context.mounted) {
                  onPageRefresh?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Redo'), duration: Duration(seconds: 1)));
                }
              },
            ),
            _Divider(),

            // ── SELECT ──
            _ToolBtn(
              icon: Icons.near_me_outlined, label: 'Select',
              active: activeTool == EditorTool.select, tooltip: 'Select tool',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.select,
            ),
            _Divider(),

            // ── WORD-LIKE TEXT EDITING ──
            _ToolBtn(
              icon: Icons.edit_document, label: 'Edit Text',
              active: activeTool == EditorTool.editText,
              color: const Color(0xFF4A9EFF),
              tooltip: 'Click any text to edit it (Word-style)',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.editText,
            ),
            _ToolBtn(
              icon: Icons.text_fields_rounded, label: 'Insert Text',
              active: activeTool == EditorTool.insertText,
              color: const Color(0xFF06D6A0),
              tooltip: 'Click anywhere to insert new text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.insertText,
            ),
            // Find & Replace
            _ToolbarIconBtn(
              icon: Icons.find_replace_rounded, tooltip: 'Find & Replace (Ctrl+H)',
              onPressed: () => showDialog(
                context: context,
                builder: (_) => FindReplaceDialog(document: document, onDone: onPageRefresh),
              ),
            ),
            _Divider(),

            // ── ANNOTATIONS ──
            _ToolBtn(
              icon: Icons.highlight, label: 'Highlight',
              active: activeTool == EditorTool.highlight,
              color: AppColors.toolHighlight, tooltip: 'Highlight text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.highlight,
            ),
            _ToolBtn(
              icon: Icons.format_underlined, label: 'Underline',
              active: activeTool == EditorTool.underline,
              color: AppColors.toolUnderline, tooltip: 'Underline text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.underline,
            ),
            _ToolBtn(
              icon: Icons.strikethrough_s, label: 'Strike',
              active: activeTool == EditorTool.strikethrough,
              color: AppColors.toolStrike, tooltip: 'Strikethrough',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.strikethrough,
            ),
            _ToolBtn(
              icon: Icons.sticky_note_2_outlined, label: 'Note',
              active: activeTool == EditorTool.text,
              color: Colors.amber, tooltip: 'Add sticky note',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.text,
            ),
            _Divider(),

            // ── PAGE OPS ──
            PopupMenuButton<String>(
              tooltip: 'Page Operations',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.insert_page_break_outlined, size: 16),
                  SizedBox(width: 4),
                  Text('Page', style: TextStyle(fontSize: 12)),
                  Icon(Icons.arrow_drop_down, size: 16),
                ]),
              ),
              onSelected: (v) => _handlePageOp(context, ref, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rotate90', child: ListTile(leading: Icon(Icons.rotate_right), title: Text('Rotate 90°'), dense: true)),
                const PopupMenuItem(value: 'rotate180', child: ListTile(leading: Icon(Icons.rotate_right), title: Text('Rotate 180°'), dense: true)),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'add_page', child: ListTile(leading: Icon(Icons.add), title: Text('Add blank page after'), dense: true)),
                const PopupMenuItem(value: 'delete_page', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Delete this page', style: TextStyle(color: Colors.red)), dense: true)),
              ],
            ),
            const SizedBox(width: 4),

            // ── DOCUMENT OPS ──
            PopupMenuButton<String>(
              tooltip: 'Document Operations',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.description_outlined, size: 16),
                  SizedBox(width: 4),
                  Text('Document', style: TextStyle(fontSize: 12)),
                  Icon(Icons.arrow_drop_down, size: 16),
                ]),
              ),
              onSelected: (v) => _handleDocOp(context, ref, v),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'watermark', child: ListTile(leading: Icon(Icons.branding_watermark_outlined), title: Text('Add Watermark'), dense: true)),
                const PopupMenuItem(value: 'protect', child: ListTile(leading: Icon(Icons.lock_outline), title: Text('Password Protect'), dense: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handlePageOp(BuildContext context, WidgetRef ref, String op) async {
    final api = ref.read(apiServiceProvider);
    final page = ref.read(currentPageProvider);
    bool ok = false;
    if (op == 'rotate90') ok = await api.rotatePage(document.fileId, page, 90);
    if (op == 'rotate180') ok = await api.rotatePage(document.fileId, page, 180);
    if (op == 'add_page') ok = await api.addBlankPage(document.fileId, page);
    if (op == 'delete_page') ok = await api.deletePage(document.fileId, page);
    if (ok && context.mounted) onPageRefresh?.call();
  }

  void _handleDocOp(BuildContext context, WidgetRef ref, String op) {
    if (op == 'watermark') {
      showDialog(context: context, builder: (_) => WatermarkDialog(document: document));
    } else if (op == 'protect') {
      showDialog(context: context, builder: (_) => PasswordDialog(document: document));
    }
  }
}

// ─── Shared toolbar widgets ──────────────────────────────────────────────────

class _ToolBtn extends ConsumerWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolBtn({
    required this.icon, required this.label, required this.active,
    this.color, required this.tooltip, required this.onPressed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = color ?? AppColors.accent;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? c.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? c : Colors.transparent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? c : Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(
                fontSize: 12, color: active ? c : Colors.grey.shade700,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconBtn({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 16,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Colors.grey.shade300,
  );
}