import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class ExcelHealthScreen extends StatefulWidget {
  const ExcelHealthScreen({super.key});

  @override
  State<ExcelHealthScreen> createState() => _ExcelHealthScreenState();
}

class _ExcelHealthScreenState extends State<ExcelHealthScreen> {
  Map<String, dynamic>? _health;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _health = await ApiService.getExcelHealth();
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      ));
    }

    final entries = _health!.entries.toList();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: entries.length,
        itemBuilder: (ctx, i) {
          final entry = entries[i];
          final data = entry.value as Map<String, dynamic>;
          final loaded = data['loaded'] == true;
          final errors = (data['errors'] as List?) ?? [];

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        loaded ? Icons.check_circle : Icons.error,
                        color: loaded
                            ? (errors.isEmpty ? const Color(0xFF2E7D32) : Colors.orange)
                            : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        data['branch_name'] ?? 'Branch ${entry.key}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Athletes: ${data['athlete_count'] ?? 0}'),
                  if (data['last_refreshed'] != null)
                    Text('Last refreshed: ${data['last_refreshed']}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (data['last_modified'] != null)
                    Text('File modified: ${data['last_modified']}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Errors:', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    for (final e in errors)
                      Text('  - $e', style: const TextStyle(fontSize: 12, color: Colors.red)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
