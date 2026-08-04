import 'athlete.dart';

class Bill {
  final String period;
  final String? amountOwed;
  final bool isPaid;
  final String? receiptNumber;
  final bool noEnrollment;
  final bool isSuspended;
  final String? branchName;
  final List<ScheduleSlot> schedule;
  final String? prevPeriod;
  final bool prevPaid;

  Bill({
    required this.period,
    this.amountOwed,
    this.isPaid = false,
    this.receiptNumber,
    this.noEnrollment = false,
    this.isSuspended = false,
    this.branchName,
    this.schedule = const [],
    this.prevPeriod,
    this.prevPaid = false,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    return Bill(
      period: json['period'] ?? '',
      amountOwed: json['amount_owed'],
      isPaid: json['is_paid'] ?? false,
      receiptNumber: json['receipt_number'],
      noEnrollment: json['no_enrollment'] ?? false,
      isSuspended: json['is_suspended'] ?? false,
      branchName: json['branch_name'],
      schedule: (json['schedule'] as List?)
              ?.map((s) => ScheduleSlot.fromJson(s))
              .toList() ??
          [],
      prevPeriod: json['prev_period'],
      prevPaid: json['prev_paid'] ?? false,
    );
  }
}
