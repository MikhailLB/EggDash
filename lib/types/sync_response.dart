// ============================================================
// SYNC RESPONSE — Parsed reply from the config endpoint.
// ============================================================
// Shape returned by the backend:
//   Gray:  { "ok": true,  "url": "https://...", "expires": 1689... }
//   White: { "ok": false, "message": "organic" }
// ============================================================

class SyncResponse {
  final bool accepted;
  final String? destination;
  final String? note;
  final int? expiresAtUnix;

  const SyncResponse({
    required this.accepted,
    this.destination,
    this.note,
    this.expiresAtUnix,
  });

  bool get hasUsableUrl =>
      accepted && destination != null && destination!.isNotEmpty;

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      accepted: json['ok'] == true,
      destination: json['url'] as String?,
      note: json['message'] as String?,
      expiresAtUnix: json['expires'] as int?,
    );
  }

  factory SyncResponse.failure(String reason) =>
      SyncResponse(accepted: false, note: reason);
}
