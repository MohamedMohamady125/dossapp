import 'package:flutter/material.dart';
import '../../models/bill.dart';
import '../../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class BillScreen extends StatefulWidget {
  const BillScreen({super.key});

  @override
  State<BillScreen> createState() => _BillScreenState();
}

class _BillScreenState extends State<BillScreen> {
  Bill? _bill;
  bool _loading = true;
  String? _error;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      _bill = await ApiService.getBill();
    } catch (e) {
      _error = e.toString();
    }
    setState(() => _loading = false);
  }

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      final intent = await ApiService.createPaymentIntent();
      final token = intent['token'];
      // Open Paymob checkout in browser
      // This presents the payment as in-person swimming lessons at a physical branch
      final url = Uri.parse('https://accept.paymob.com/api/acceptance/iframes/0?payment_token=$token');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment error: $e')),
        );
      }
    }
    setState(() => _paying = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Bill')),
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
              : RefreshIndicator(onRefresh: _load, child: _buildContent()),
    );
  }

  Widget _buildContent() {
    final bill = _bill!;

    if (bill.noEnrollment) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No Active Enrollment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('You are not enrolled for the current period.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Period
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  _formatPeriod(bill.period),
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  bill.amountOwed != null ? '${bill.amountOwed} EGP' : 'Pending',
                  style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Store-acceptance framing: clearly present as in-person service
                if (bill.branchName != null)
                  Text(
                    'In-person swimming lessons at ${bill.branchName}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                if (bill.schedule.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  for (final s in bill.schedule)
                    Text(
                      '${s.dayPair ?? ""} ${s.timeBlock ?? ""}'
                      '${s.coach != null ? " — Coach: ${s.coach}" : ""}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (bill.isPaid) ...[
          Card(
            color: const Color(0xFFE8F5E9),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, size: 48, color: Color(0xFF2E7D32)),
                  const SizedBox(height: 8),
                  const Text('PAID', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                  if (bill.receiptNumber != null) ...[
                    const SizedBox(height: 4),
                    Text('Receipt: ${bill.receiptNumber}', style: const TextStyle(color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ),
        ] else if (bill.amountOwed != null) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _paying ? null : _pay,
              icon: _paying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.payment),
              label: Text(_paying ? 'Processing...' : 'Pay ${bill.amountOwed} EGP'),
            ),
          ),
        ] else ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.hourglass_empty, size: 48, color: Colors.orange),
                  SizedBox(height: 8),
                  Text('Bill Pending', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Your bill amount has not been set yet.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ],
      ],
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
