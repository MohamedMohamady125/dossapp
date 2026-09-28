class MonthlyReport {
  final int id;
  final int branchId;
  final int athleteNumber;
  final String? athleteName;
  final String period; // YYYY-MM
  final int technique;
  final int endurance;
  final int commitment;
  final int discipline;
  final String? coachNotes;
  final String? goals;
  final String createdByName;
  final String createdByRole;
  final DateTime? updatedAt;

  MonthlyReport({
    required this.id,
    required this.branchId,
    required this.athleteNumber,
    this.athleteName,
    required this.period,
    required this.technique,
    required this.endurance,
    required this.commitment,
    required this.discipline,
    this.coachNotes,
    this.goals,
    required this.createdByName,
    required this.createdByRole,
    this.updatedAt,
  });

  double get overall => (technique + endurance + commitment + discipline) / 4.0;

  factory MonthlyReport.fromJson(Map<String, dynamic> json) {
    return MonthlyReport(
      id: json['id'],
      branchId: json['branch_id'],
      athleteNumber: json['athlete_number'],
      athleteName: json['athlete_name'],
      period: json['period'],
      technique: json['technique'],
      endurance: json['endurance'],
      commitment: json['commitment'],
      discipline: json['discipline'],
      coachNotes: json['coach_notes'],
      goals: json['goals'],
      createdByName: json['created_by_name'] ?? '',
      createdByRole: json['created_by_role'] ?? '',
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at']) : null,
    );
  }
}

class ReportSwimmer {
  final int athleteNumber;
  final String name;
  final bool hasCurrentReport;

  ReportSwimmer({required this.athleteNumber, required this.name, required this.hasCurrentReport});

  factory ReportSwimmer.fromJson(Map<String, dynamic> json) {
    return ReportSwimmer(
      athleteNumber: json['athlete_number'],
      name: json['name'] ?? '',
      hasCurrentReport: json['has_current_report'] ?? false,
    );
  }
}
