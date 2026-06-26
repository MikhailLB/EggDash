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
//   • Success + `ok=true` + `url`  → caller flips ShellMode.online
//                                    and routes to that fresh URL.
//                                    URL is NEVER cached — every
//                                    launch re-asks config.
//   • Success + `ok=false`         → caller flips ShellMode.offline
//                                    (this decision is sticky).
//   • Any error / timeout (>15 s)  → return failure; caller routes
//                                    the user to DropoutStage.
//   • Endpoint not configured      → fail fast — empty URL is
//                                    indistinguishable from a
//                                    deliberately disabled build.
//
// NO URL CACHE: by design we do not persist `url` / `expires`.
// Each cold start hits the config endpoint and uses whatever URL
// the backend serves at that moment. The only persisted launch-
// time URL is the one-shot push URL stashed by AlertCenter on a
// cold-start notification tap.
// ============================================================

class SyncGateway {
  SyncGateway(this._vault);

  // Kept as a constructor argument for API symmetry — the gateway
  // has nothing to write right now, but downstream wiring depends
  // on the same handshake() / constructor contract.
  // ignore: unused_field
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

      return SyncResponse.fromJson(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('[SyncGateway] exception: $e');
      return SyncResponse.failure(e.toString());
    }
  }
}
