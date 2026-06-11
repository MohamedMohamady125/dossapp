class Receipt {
  final int id;
  final String receiptNumber;
  final String period;
  final String amountPaid;
  final String paymentChannel;
  final DateTime issuedAt;
  final String athleteName;
  final String branchName;
  final String? level;
  final bool pdfAvailable;

  Receipt({
    required this.id,
    required this.receiptNumber,
    required this.period,
    required this.amountPaid,
    required this.paymentChannel,
    required this.issuedAt,
    required this.athleteName,
    required this.branchName,
    this.level,
    this.pdfAvailable = false,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'],
      receiptNumber: json['receipt_number'] ?? '',
      period: json['period'] ?? '',
      amountPaid: json['amount_paid'] ?? '',
      paymentChannel: json['payment_channel'] ?? '',
      issuedAt: DateTime.parse(json['issued_at']),
      athleteName: json['athlete_name'] ?? '',
      branchName: json['branch_name'] ?? '',
      level: json['level'],
      pdfAvailable: json['pdf_available'] ?? false,
    );
  }
}
