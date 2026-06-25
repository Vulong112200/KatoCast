import 'package:flutter/material.dart';

import '../../core/error/failures.dart';

/// Hiển thị khi quyền vị trí bị từ chối. Cho phép thử lại hoặc mở Cài đặt
/// (khi từ chối vĩnh viễn) — app không crash, hướng dẫn người dùng xử lý.
class PermissionDeniedWidget extends StatelessWidget {
  final PermissionFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const PermissionDeniedWidget({
    super.key,
    required this.failure,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 56, color: Colors.orange),
            const SizedBox(height: 12),
            Text(
              failure.userMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (failure.permanentlyDenied)
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Mở cài đặt'),
              )
            else
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.my_location),
                label: const Text('Cấp quyền vị trí'),
              ),
          ],
        ),
      ),
    );
  }
}
