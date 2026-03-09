import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/page_thumbnail_panel.dart';
import '../widgets/pdf_viewer_area.dart';
import '../widgets/annotation_tools_panel.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final PdfDocument document;
  const EditorScreen({super.key, required this.document});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with TickerProviderStateMixin {
  late final AnimationController _sidebarAnim;
  bool _showAnnotationPanel = false;

  @override
  void initState() {
    super.initState();
    _sidebarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _sidebarAnim.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    final visible = ref.read(sidebarVisibleProvider);
    if (visible) {
      _sidebarAnim.reverse();
    } else {
      _sidebarAnim.forward();
    }
    ref.read(sidebarVisibleProvider.notifier).state = !visible;
  }

  @override
  Widget build(BuildContext context) {
    final activeTool = ref.watch(activeToolProvider);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          // ── Editor Toolbar ────────────────────────────────────────────
          EditorToolbar(
            document: widget.document,
            onToggleSidebar: _toggleSidebar,
            onToggleAnnotations: () {
              setState(() => _showAnnotationPanel = !_showAnnotationPanel);
            },
            onPageRefresh: () => setState(() {}),
          ),

          // ── Main Content ──────────────────────────────────────────────
          Expanded(
            child: Row(
              children: [
                // Page Thumbnail Sidebar
                if (!isMobile)
                  SizeTransition(
                    sizeFactor: CurvedAnimation(
                      parent: _sidebarAnim,
                      curve: Curves.easeInOut,
                    ),
                    axis: Axis.horizontal,
                    child: PageThumbnailPanel(document: widget.document),
                  ),

                // PDF Viewer
                Expanded(
                  child: Stack(
                    children: [
                      PdfViewerArea(document: widget.document),
                      // Annotation tools overlay
                      if (_showAnnotationPanel)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: AnnotationToolsPanel(
                            document: widget.document,
                            onClose: () =>
                                setState(() => _showAnnotationPanel = false),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom Page Navigation (mobile) ───────────────────────────
          if (isMobile) _BottomPageNav(document: widget.document),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final currentPage = ref.watch(currentPageProvider);
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.document.displayName,
            style: Theme.of(context).textTheme.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Page $currentPage of ${widget.document.pageCount}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        // Zoom controls
        IconButton(
          icon: const Icon(Icons.zoom_out_rounded),
          onPressed: () {
            final z = ref.read(zoomLevelProvider);
            if (z > 0.5) ref.read(zoomLevelProvider.notifier).state = z - 0.25;
          },
          tooltip: 'Zoom out',
        ),
        Consumer(builder: (ctx, r, _) {
          final zoom = r.watch(zoomLevelProvider);
          return GestureDetector(
            onTap: () => ref.read(zoomLevelProvider.notifier).state = 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${(zoom * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent,
                ),
              ),
            ),
          );
        }),
        IconButton(
          icon: const Icon(Icons.zoom_in_rounded),
          onPressed: () {
            final z = ref.read(zoomLevelProvider);
            if (z < 3.0) ref.read(zoomLevelProvider.notifier).state = z + 0.25;
          },
          tooltip: 'Zoom in',
        ),
        const SizedBox(width: 4),
        // Save button
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ElevatedButton.icon(
            onPressed: () => _saveDocument(context),
            icon: const Icon(Icons.save_alt_rounded, size: 18),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
            ),
          ),
        ),
      ],
    );
  }

  void _saveDocument(BuildContext context) {
    final api = ref.read(apiServiceProvider);
    final doc = widget.document;
    final url = api.getDownloadUrl(doc.fileId);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Saving PDF...'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
    // In production: trigger download or share
  }
}

// ── Bottom Page Navigation (mobile only) ─────────────────────────────────────

class _BottomPageNav extends ConsumerWidget {
  final PdfDocument document;
  const _BottomPageNav({required this.document});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(currentPageProvider);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: page > 1
                ? () => ref.read(currentPageProvider.notifier).state = page - 1
                : null,
          ),
          const SizedBox(width: 16),
          Text(
            '$page / ${document.pageCount}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: page < document.pageCount
                ? () => ref.read(currentPageProvider.notifier).state = page + 1
                : null,
          ),
        ],
      ),
    );
  }
}