import 'athlete.dart';

class Bill {
  final String period;
  final String? amountOwed;
  final bool isPaid;
  final String? receiptNumber;
  final bool noEnrollment;
  final String? branchName;
  final List<ScheduleSlot> schedule;

  Bill({
    required this.period,
    this.amountOwed,
    this.isPaid = false,
    this.receiptNumber,
    this.noEnrollment = false,
    this.branchName,
    this.schedule = const [],
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      period: json['period'] ?? '',
      amountOwed: json['amount_owed'],
      isPaid: json['is_paid'] ?? false,
      receiptNumber: json['receipt_number'],
      noEnrollment: json['no_enrollment'] ?? false,
      branchName: json['branch_name'],
      schedule: (json['schedule'] as List?)
              ?.map((s) => ScheduleSlot.fromJson(s))
              .toList() ??
          [],
    );
  }
}
