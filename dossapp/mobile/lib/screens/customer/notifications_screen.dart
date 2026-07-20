import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../utils/theme.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/animated_list_item.dart';
import '../../widgets/empty_state.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onUnreadChanged;
  const NotificationsScreen({super.key, this.onUnreadChanged});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ApiService.getNotifications();
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['is_read'] == true) return;
    setState(() => item['is_read'] = true);
    try {
      await ApiService.markNotificationRead(item['id'] as int);
      widget.onUnreadChanged?.call();
    } catch (e) {
      // Revert optimistic update on failure
      if (mounted) {
        setState(() => item['is_read'] = false);
      }
    }
  }

  Future<void> _markAllRead() async {
    final previousStates = {for (final item in _items) item['id']: item['is_read']};
    setState(() {
      for (final item in _items) {
        item['is_read'] = true;
      }
    });
    try {
      await ApiService.markAllNotificationsRead();
      widget.onUnreadChanged?.call();
    } catch (e) {
      // Revert optimistic update on failure
      if (mounted) {
        setState(() {
          for (final item in _items) {
            item['is_read'] = previousStates[item['id']] ?? false;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'schedule_change':
        return Icons.calendar_month_rounded;
      case 'payment_reminder':
        return Icons.payments_rounded;
      case 'missed_sessions':
        return Icons.favorite_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'schedule_change':
        return AppColors.primary;
      case 'payment_reminder':
        return AppColors.warning;
      case 'missed_sessions':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return DateFormat('h:mm a').format(dt);
      }
      return DateFormat('d MMM').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => n['is_read'] != true);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonList(count: 5, hasAvatar: true);
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'No Notifications Yet',
        subtitle: 'You will receive updates about schedules, payments, and more.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final item = _items[i];
          final type = (item['type'] ?? '') as String;
          final isRead = item['is_read'] == true;
          final color = _colorFor(type);

          return AnimatedListItem(
            index: i,
            child: InkWell(
              onTap: () => _markRead(item),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isRead ? Colors.white : AppColors.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isRead ? AppColors.border : AppColors.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(_iconFor(type), size: 20, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  (item['title'] ?? '') as String,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                _formatDate(item['created_at'] as String?),
                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (item['body'] ?? '') as String,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (!isRead)
                      Container(
                        margin: const EdgeInsets.only(left: 8, top: 4),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
