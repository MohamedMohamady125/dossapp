/// A monthly report: an uploaded PDF, a written note, or a PDF with a note.
class MonthlyReport {
  final int id;
  final int branchId;
  final int athleteNumber;
  final String? athleteName;
  final String period; // YYYY-MM
  final String? note;
  final bool hasPdf;
  final String? pdfFilename;
  final String createdByName;
  final String createdByRole;
  final DateTime? updatedAt;

  MonthlyReport({
    required this.id,
    required this.branchId,
    required this.athleteNumber,
    this.athleteName,
    required this.period,
    this.note,
    this.hasPdf = false,
    this.pdfFilename,
    required this.createdByName,
    required this.createdByRole,
    this.updatedAt,
  });

  factory MonthlyReport.fromJson(Map<String, dynamic> json) {
    // Reports written before notes and goals were merged keep both texts.
    final parts = [json['coach_notes'], json['goals']]
        .whereType<String>()
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    return MonthlyReport(
      id: json['id'],
      branchId: json['branch_id'],
      athleteNumber: json['athlete_number'],
      athleteName: json['athlete_name'],
      period: json['period'],
      note: parts.isEmpty ? null : parts.join('\n\n'),
      hasPdf: json['has_pdf'] ?? false,
      pdfFilename: json['pdf_filename'],
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
