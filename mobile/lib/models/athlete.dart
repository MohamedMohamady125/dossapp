class ScheduleSlot {
  final String? coach;
  final String? timeBlock;
  final String? dayPair;

  ScheduleSlot({this.coach, this.timeBlock, this.dayPair});

  factory ScheduleSlot.fromJson(Map<String, dynamic> json) {
    return ScheduleSlot(
      coach: json['coach'],
      timeBlock: json['time_block'],
      dayPair: json['day_pair'],
    );
  }
}

class AthleteProfile {
  final String branch;
  final int branchId;
  final int athleteNumber;
  final String name;
  final double? age;
  final String? dateOfBirth;
  final String? gender;
  final String? level;
  final String? type;
  final String? days;
  final String? sessions;
  final String? segment;
  final List<ScheduleSlot> schedule;

  AthleteProfile({
    required this.branch,
    required this.branchId,
    required this.athleteNumber,
    required this.name,
    this.age,
    this.dateOfBirth,
    this.gender,
    this.level,
    this.type,
    this.days,
    this.sessions,
    this.segment,
    this.schedule = const [],
  });

  factory AthleteProfile.fromJson(Map<String, dynamic> json) {
    return AthleteProfile(
      branch: json['branch'] ?? '',
      branchId: json['branch_id'] ?? 0,
      athleteNumber: json['athlete_number'] ?? 0,
      name: json['name'] ?? '',
      age: json['age']?.toDouble(),
      dateOfBirth: json['date_of_birth'],
      gender: json['gender'],
      level: json['level'],
      type: json['type'],
      days: json['days'],
      sessions: json['sessions'],
      segment: json['segment'],
      schedule: (json['schedule'] as List?)
              ?.map((s) => ScheduleSlot.fromJson(s))
              .toList() ??
          [],
    );
  }
}

class AthleteDetail extends AthleteProfile {
  final String? pay;
  final String? phone1;
  final String? phone2;
  final String? comment;
  final String? receiptNo;
  final bool hasAccount;

  AthleteDetail({
    required super.branch,
    required super.branchId,
    required super.athleteNumber,
    required super.name,
    super.age,
    super.dateOfBirth,
    super.gender,
    super.level,
    super.type,
    super.days,
    super.sessions,
    super.segment,
    super.schedule,
    this.pay,
    this.phone1,
    this.phone2,
    this.comment,
    this.receiptNo,
    this.hasAccount = false,
  });

  factory AthleteDetail.fromJson(Map<String, dynamic> json) {
    return AthleteDetail(
      branch: json['branch'] ?? '',
      branchId: json['branch_id'] ?? 0,
      athleteNumber: json['athlete_number'] ?? 0,
      name: json['name'] ?? '',
      age: json['age']?.toDouble(),
      dateOfBirth: json['date_of_birth'],
      gender: json['gender'],
      level: json['level'],
      type: json['type'],
      days: json['days'],
      sessions: json['sessions'],
      segment: json['segment'],
      pay: json['pay'],
      phone1: json['phone1'],
      phone2: json['phone2'],
      comment: json['comment'],
      receiptNo: json['receipt_no'],
      hasAccount: json['has_account'] ?? false,
      schedule: (json['schedule'] as List?)
              ?.map((s) => ScheduleSlot.fromJson(s))
              .toList() ??
          [],
    );
  }
}
