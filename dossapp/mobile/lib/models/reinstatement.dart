class ReinstatementStatus {
  final String status; // none | pending | approved | declined
  final String? createdAt;
  final String? adminNote;

  ReinstatementStatus({
    required this.status,
    this.createdAt,
    this.adminNote,
  });

  factory ReinstatementStatus.fromJson(Map<String, dynamic> json) {
    return ReinstatementStatus(
      status: json['status'] ?? 'none',
      createdAt: json['created_at'],
      adminNote: json['admin_note'],
    );
  }

  bool get isNone => status == 'none';
  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDeclined => status == 'declined';
}
