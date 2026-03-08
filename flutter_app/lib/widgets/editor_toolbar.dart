import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'watermark_dialog.dart';
import 'password_dialog.dart';

class EditorToolbar extends ConsumerWidget {
  final PdfDocument document;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleAnnotations;

  const EditorToolbar({
    super.key,
    required this.document,
    required this.onToggleSidebar,
    required this.onToggleAnnotations,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTool = ref.watch(activeToolProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface2 : AppColors.lightSurface2,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // ── Sidebar toggle ──────────────────────────────────────────
            _ToolbarIconBtn(
              icon: Icons.view_sidebar_outlined,
              tooltip: 'Toggle page panel',
              onPressed: onToggleSidebar,
            ),

            _Divider(),

            // ── Selection tools ─────────────────────────────────────────
            _ToolBtn(
              icon: Icons.near_me_outlined,
              label: 'Select',
              active: activeTool == EditorTool.select,
              tooltip: 'Select tool',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.select,
            ),

            _Divider(),

            // ── Annotation tools ────────────────────────────────────────
            _ToolBtn(
              icon: Icons.highlight,
              label: 'Highlight',
              active: activeTool == EditorTool.highlight,
              color: AppColors.toolHighlight,
              tooltip: 'Highlight text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.highlight,
            ),
            _ToolBtn(
              icon: Icons.format_underlined,
              label: 'Underline',
              active: activeTool == EditorTool.underline,
              color: AppColors.toolUnderline,
              tooltip: 'Underline text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.underline,
            ),
            _ToolBtn(
              icon: Icons.strikethrough_s,
              label: 'Strike',
              active: activeTool == EditorTool.strikethrough,
              color: AppColors.toolStrike,
              tooltip: 'Strikethrough',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.strikethrough,
            ),
            _ToolBtn(
              icon: Icons.text_fields_rounded,
              label: 'Text',
              active: activeTool == EditorTool.text,
              color: AppColors.toolText,
              tooltip: 'Add text',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.text,
            ),
            _ToolBtn(
              icon: Icons.draw_outlined,
              label: 'Draw',
              active: activeTool == EditorTool.draw,
              color: AppColors.toolDraw,
              tooltip: 'Freehand draw',
              onPressed: () => ref.read(activeToolProvider.notifier).state = EditorTool.draw,
            ),

            _Divider(),

            // ── Annotation Panel ────────────────────────────────────────
            _ToolbarIconBtn(
              icon: Icons.sticky_note_2_outlined,
              tooltip: 'Annotation panel',
              onPressed: onToggleAnnotations,
            ),

            _Divider(),

            // ── Page operations ─────────────────────────────────────────
            PopupMenuButton<String>(
              tooltip: 'Page tools',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: const [
                    Icon(Icons.insert_drive_file_outlined, size: 18),
                    SizedBox(width: 4),
                    Text('Page', style: TextStyle(fontSize: 12)),
                    Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
              onSelected: (value) => _handlePageTool(context, ref, value),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rotate_90', child: Row(
                  children: [Icon(Icons.rotate_right, size: 18), SizedBox(width: 8), Text('Rotate 90°')],
                )),
                const PopupMenuItem(value: 'rotate_180', child: Row(
                  children: [Icon(Icons.rotate_left, size: 18), SizedBox(width: 8), Text('Rotate 180°')],
                )),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Row(
                  children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete page', style: TextStyle(color: Colors.red))],
                )),
              ],
            ),

            // ── Document operations ──────────────────────────────────────
            PopupMenuButton<String>(
              tooltip: 'Document tools',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: const [
                    Icon(Icons.more_horiz_rounded, size: 18),
                    SizedBox(width: 4),
                    Text('More', style: TextStyle(fontSize: 12)),
                    Icon(Icons.arrow_drop_down, size: 16),
                  ],
                ),
              ),
              onSelected: (value) => _handleDocTool(context, ref, value),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'watermark', child: Row(
                  children: [Icon(Icons.water_outlined, size: 18), SizedBox(width: 8), Text('Add watermark')],
                )),
                const PopupMenuItem(value: 'password', child: Row(
                  children: [Icon(Icons.lock_outline, size: 18), SizedBox(width: 8), Text('Password protect')],
                )),
                const PopupMenuItem(value: 'split', child: Row(
                  children: [Icon(Icons.call_split_rounded, size: 18), SizedBox(width: 8), Text('Split PDF')],
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handlePageTool(BuildContext context, WidgetRef ref, String tool) {
    final api = ref.read(apiServiceProvider);
    final page = ref.read(currentPageProvider);
    switch (tool) {
      case 'rotate_90':
        api.rotatePage(document.fileId, page, 90).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Page rotated 90°')),
          );
        });
      case 'rotate_180':
        api.rotatePage(document.fileId, page, 180).then((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Page rotated 180°')),
          );
        });
    }
  }

  void _handleDocTool(BuildContext context, WidgetRef ref, String tool) {
    switch (tool) {
      case 'watermark':
        showDialog(
          context: context,
          builder: (_) => WatermarkDialog(document: document),
        );
      case 'password':
        showDialog(
          context: context,
          builder: (_) => PasswordDialog(document: document),
        );
    }
  }
}

// ── Toolbar Icon Button ────────────────────────────────────────────────────────

class _ToolbarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

// ── Tool Button ───────────────────────────────────────────────────────────────

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color? color;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.active,
    this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.accent;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? effectiveColor.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? effectiveColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: active ? effectiveColor : null),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? effectiveColor : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Vertical Divider ──────────────────────────────────────────────────────────

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Theme.of(context).dividerColor,
    );
  }
}
