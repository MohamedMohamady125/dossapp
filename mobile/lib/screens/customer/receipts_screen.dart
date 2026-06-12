import 'package:flutter/material.dart';
import '../../models/receipt.dart';
import '../../services/api_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  List<Receipt>? _receipts;
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
      _receipts = await ApiService.getReceipts();
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Receipts')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ))
              : _receipts!.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No receipts yet', style: TextStyle(fontSize: 18, color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _receipts!.length,
                        itemBuilder: (ctx, i) => _buildReceiptCard(_receipts![i]),
                      ),
                    ),
    );
  }

  Widget _buildReceiptCard(Receipt receipt) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(receipt.receiptNumber, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('PAID', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${receipt.amountPaid} EGP', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${receipt.paymentChannel} | ${_formatPeriod(receipt.period)}', style: const TextStyle(color: Colors.grey)),
            Text(DateFormat('dd MMM yyyy, hh:mm a').format(receipt.issuedAt), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (receipt.pdfAvailable)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    onPressed: () {
                      // TODO(spec): Download PDF via http and open
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Downloading receipt PDF...')),
                      );
                    },
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                  onPressed: () {
                    SharePlus.instance.share(
                      ShareParams(text: 'Aqua Athletic Receipt ${receipt.receiptNumber}\n'
                          'Amount: ${receipt.amountPaid} EGP\n'
                          'Period: ${receipt.period}'),
                    );
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Resend'),
                  onPressed: () async {
                    try {
                      await ApiService.resendReceipt(receipt.id);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Receipt resend queued')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatPeriod(String period) {
    try {
      final parts = period.split('-');
      final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[int.parse(parts[1])]} ${parts[0]}';
    } catch (_) {
      return period;
    }
  }
}
