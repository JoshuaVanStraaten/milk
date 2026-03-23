import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/list_provider.dart';

/// Show the share list bottom sheet.
void showShareListSheet(
  BuildContext context,
  WidgetRef ref, {
  required String listId,
  required String listName,
  String? ownerEmail,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareListSheet(
      listId: listId,
      listName: listName,
      ownerEmail: ownerEmail,
    ),
  );
}

class _ShareListSheet extends ConsumerStatefulWidget {
  final String listId;
  final String listName;
  final String? ownerEmail;

  const _ShareListSheet({
    required this.listId,
    required this.listName,
    this.ownerEmail,
  });

  @override
  ConsumerState<_ShareListSheet> createState() => _ShareListSheetState();
}

class _ShareListSheetState extends ConsumerState<_ShareListSheet> {
  final _emailController = TextEditingController();
  bool _isSending = false;
  String? _statusMessage;
  bool _statusIsError = false;
  Timer? _statusTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  void _showStatus(String message, {bool isError = false}) {
    _statusTimer?.cancel();
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    _statusTimer = Timer(Duration(seconds: isError ? 4 : 3), () {
      if (mounted) {
        setState(() => _statusMessage = null);
      }
    });
  }

  Future<void> _shareWithEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    // Basic email validation
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      _showStatus('Please enter a valid email address', isError: true);
      return;
    }

    setState(() => _isSending = true);

    try {
      await ref.read(listNotifierProvider.notifier).shareList(
            listId: widget.listId,
            shareWithEmail: email,
          );

      _emailController.clear();
      ref.invalidate(sharedUsersProvider(widget.listId));
      ref.invalidate(userListsProvider);

      if (mounted) {
        _showStatus('Shared with $email');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        _showStatus(msg, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _removeUser(String email) async {
    try {
      await ref.read(listRepositoryProvider).unshareList(
            listId: widget.listId,
            sharedWithEmail: email,
          );

      ref.invalidate(sharedUsersProvider(widget.listId));
      ref.invalidate(userListsProvider);

      if (mounted) {
        _showStatus('Removed $email');
      }
    } catch (e) {
      if (mounted) {
        _showStatus('Failed to remove: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sharedUsers = ref.watch(sharedUsersProvider(widget.listId));
    final currentEmail = SupabaseConfig.currentUser?.email;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[600] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.share,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Share "${widget.listName}"',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Email input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _shareWithEmail(),
                    decoration: InputDecoration(
                      hintText: 'Enter email to share with',
                      prefixIcon: const Icon(Icons.email_outlined),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isSending
                    ? const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        onPressed: _shareWithEmail,
                        icon: const Icon(Icons.send),
                        color: AppColors.primary,
                        tooltip: 'Share',
                      ),
              ],
            ),
          ),

          // Inline status message
          if (_statusMessage != null)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: (_statusIsError ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusIsError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 16,
                      color:
                          _statusIsError ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _statusIsError
                              ? AppColors.error
                              : AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Collaborators section
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'People with access',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),

          // Owner row
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: const Icon(Icons.person, color: AppColors.primary),
            ),
            title: Text(
              widget.ownerEmail ?? currentEmail ?? 'You',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Owner',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Shared users list (exclude the owner)
          sharedUsers.when(
            data: (allUsers) {
              final ownerAddr = (widget.ownerEmail ?? currentEmail ?? '')
                  .toLowerCase();
              final users = allUsers
                  .where((e) => e.toLowerCase() != ownerAddr)
                  .toList();
              if (users.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Not shared with anyone yet',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final email = users[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isDark
                          ? Colors.grey[700]
                          : Colors.grey[200],
                      child: Icon(
                        Icons.person_outline,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    title: Text(
                      email,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: AppColors.error,
                      tooltip: 'Remove',
                      onPressed: () => _removeUser(email),
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Could not load collaborators',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
