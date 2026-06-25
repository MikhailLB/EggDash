import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../setup/core_settings.dart';
import '../types/sync_response.dart';
import 'data_vault.dart';
import 'transport_pipe.dart';

// ============================================================
// SYNC GATEWAY — POST attribution payload to the config endpoint
// ============================================================
// Receives a fully-merged attribution body, sends it as JSON to
// the backend, and returns a parsed SyncResponse.
//
//   • Success + `ok=true` + `url`     → save url/expires to vault,
//                                       caller flips ShellMode.online.
//   • Success + `ok=false`            → caller flips ShellMode.offline
//                                       (this decision is sticky).
//   • Any error / timeout (>15 s)     → return failure; caller may
//                                       fall back to a previously
//                                       saved url if one exists.
//   • Endpoint not configured         → fail fast — empty URL is
//                                       indistinguishable from a
//                                       deliberately disabled build.
// ============================================================

class SyncGateway {
  SyncGateway(this._vault);

  final DataVault _vault;

  Future<SyncResponse> handshake(Map<String, dynamic> payload) async {
    final endpoint = CoreSettings.syncGatewayUrl;
    if (endpoint.isEmpty) {
      return SyncResponse.failure('endpoint_unconfigured');
    }

    try {
      final uri = Uri.parse(endpoint);
      final resp = await TransportPipe.instance
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(CoreSettings.syncRequestTimeout);

      if (resp.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[SyncGateway] http ${resp.statusCode}: ${resp.body}');
        }
        return SyncResponse.failure('http_${resp.statusCode}');
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        return SyncResponse.failure('malformed_response');
      }

      final parsed = SyncResponse.fromJson(decoded);
      if (parsed.hasUsableUrl) {
        await _vault.saveDestination(parsed.destination!);
        if (parsed.expiresAtUnix != null) {
          await _vault.writeExpiresAt(parsed.expiresAtUnix!);
        }
        await _vault.stampLastSync();
      }
      return parsed;
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncGateway] exception: $e');
      return SyncResponse.failure(e.toString());
    }
  }
}
