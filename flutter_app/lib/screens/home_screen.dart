import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_providers.dart';
import '../models/pdf_document.dart';
import '../theme/app_theme.dart';
import '../widgets/pdf_card.dart';
import '../widgets/empty_state.dart';
import 'editor_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentDocs = ref.watch(recentDocsProvider);
    final uploadState = ref.watch(uploadProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: scheme.background,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 24, bottom: 16),
              title: Text(
                'PDFForge',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.lightText,
                  fontSize: 28,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () => _showSearch(context),
                tooltip: 'Search files',
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _showSettings(context),
                tooltip: 'Settings',
              ),
              const SizedBox(width: 8),
            ],
          ),

          // ── Quick Actions ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _QuickActions(onOpenFile: () => _pickFile(context, ref)),
            ),
          ),

          // ── Recent Files Section ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Row(
                children: [
                  Text(
                    'Recent Files',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Spacer(),
                  if (recentDocs.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          ref.read(recentDocsProvider.notifier).clear(),
                      child: Text(
                        'Clear all',
                        style: TextStyle(color: scheme.secondary),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Upload Progress ───────────────────────────────────────────────
          if (uploadState.status == UploadStatus.uploading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _UploadingCard(),
              ),
            ),

          if (uploadState.status == UploadStatus.error)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: _ErrorBanner(message: uploadState.errorMessage ?? 'Upload failed'),
              ),
            ),

          // ── File Grid ────────────────────────────────────────────────────
          recentDocs.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: EmptyState(onOpenFile: () => _pickFile(context, ref)),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.72,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => PdfCard(
                        document: recentDocs[index],
                        onTap: () => _openDocument(context, ref, recentDocs[index]),
                        onDelete: () => ref
                            .read(recentDocsProvider.notifier)
                            .removeDocument(recentDocs[index].fileId),
                      ),
                      childCount: recentDocs.length,
                    ),
                  ),
                ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pickFile(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Open PDF'),
      ),
    );
  }

  Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final doc = await ref.read(uploadProvider.notifier).uploadFile(file);
      if (doc != null && context.mounted) {
        _openDocument(context, ref, doc);
      }
    }
  }

  void _openDocument(BuildContext context, WidgetRef ref, PdfDocument doc) {
    ref.read(activeDocumentProvider.notifier).state = doc;
    ref.read(currentPageProvider.notifier).state = 1;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(document: doc)),
    );
  }

  void _showSearch(BuildContext context) {
    showSearch(context: context, delegate: _PdfSearchDelegate());
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SettingsSheet(),
    );
  }
}

// ── Quick Actions Widget ──────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onOpenFile;
  const _QuickActions({required this.onOpenFile});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.accent.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit PDFs like a pro',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Annotate, merge, split, and sign — all in one place.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: onOpenFile,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Open PDF'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
                onPressed: () {},
                icon: const Icon(Icons.merge_type_rounded, size: 18),
                label: const Text('Merge'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Upload Card ───────────────────────────────────────────────────────────────

class _UploadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withOpacity(0.3)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
          ),
          SizedBox(width: 12),
          Text('Uploading PDF...'),
        ],
      ),
    );
  }
}

// ── Error Banner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends ConsumerWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: TextStyle(color: Colors.red.shade700))),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => ref.read(uploadProvider.notifier).reset(),
            color: Colors.red.shade700,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

// ── Search Delegate ───────────────────────────────────────────────────────────

class _PdfSearchDelegate extends SearchDelegate<String> {
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
  ];

  @override
  Widget buildLeading(BuildContext context) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(context, ''));

  @override
  Widget buildResults(BuildContext context) => const Center(child: Text('No results'));

  @override
  Widget buildSuggestions(BuildContext context) => const Center(child: Text('Type to search'));
}

// ── Settings Sheet ────────────────────────────────────────────────────────────

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Settings', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 24),
            _SettingsTile(icon: Icons.cloud_outlined, label: 'Server URL', value: 'localhost:8000'),
            _SettingsTile(icon: Icons.dark_mode_outlined, label: 'Theme', value: 'System'),
            _SettingsTile(icon: Icons.info_outline, label: 'Version', value: '1.0.0'),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SettingsTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent),
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.bodySmall),
      onTap: () {},
    );
  }
}
