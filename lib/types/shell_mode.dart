// ============================================================
// SHELL MODE — Top-level runtime mode for the dual-path app.
// ============================================================
// Online (gray): the backend assigned this install a WebView URL.
// Offline (white): the backend declined or no connectivity — the
//                   native egg-catching game owns the screen.
// Pending: very first launch, no decision yet.
// ============================================================

enum ShellMode {
  online,
  offline,
  pending;

  static const _storageKeyOnline = 'mode_online';
  static const _storageKeyOffline = 'mode_offline';
  static const _storageKeyPending = 'mode_pending';

  String toStorageValue() {
    switch (this) {
      case ShellMode.online:
        return _storageKeyOnline;
      case ShellMode.offline:
        return _storageKeyOffline;
      case ShellMode.pending:
        return _storageKeyPending;
    }
  }

  static ShellMode parse(String? raw) {
    if (raw == _storageKeyOnline) return ShellMode.online;
    if (raw == _storageKeyOffline) return ShellMode.offline;
    return ShellMode.pending;
  }
}
