// ─────────────────────────────────────────────────────────────────────────────
// page_thumbnail_panel.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pdf_document.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class PageThumbnailPanel extends ConsumerWidget {
  final PdfDocument document;
  const PageThumbnailPanel({super.key, required this.document});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPage = ref.watch(currentPageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: document.pageCount,
        itemBuilder: (context, index) {
          final page = index + 1;
          final isActive = page == currentPage;
          return GestureDetector(
            onTap: () => ref.read(currentPageProvider.notifier).state = page,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: isActive
                    ? [BoxShadow(color: AppColors.accent.withOpacity(0.2), blurRadius: 6)]
                    : null,
              ),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _ThumbnailImage(fileId: document.fileId, page: page),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '$page',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                        color: isActive ? AppColors.accent : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ThumbnailImage extends ConsumerWidget {
  final String fileId;
  final int page;
  const _ThumbnailImage({required this.fileId, required this.page});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(pageImageProvider((fileId, page)));
    return imageAsync.when(
      loading: () => Container(
        height: 80,
        color: Colors.grey.shade200,
        child: const Center(child: SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        )),
      ),
      error: (_, __) => Container(
        height: 80,
        color: Colors.grey.shade100,
        child: const Icon(Icons.description_outlined, size: 28, color: Colors.grey),
      ),
      data: (b64) => Image.memory(
        base64Decode(b64),
        height: 80,
        fit: BoxFit.cover,
      ),
    );
  }
}
