import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api_server/local_api_server.dart';
import 'remote_access_provider.dart';

/// Coordinates the lifecycle of the remote HTTPS tunnel with the [LocalApiServer].
///
/// Guarantees:
/// 1. Remote access is disabled by default.
/// 2. Remote access cannot be started unless [LocalApiServer] is running.
/// 3. Stopping [LocalApiServer] immediately stops the remote access tunnel.
/// 4. Disposing the manager or application shuts down the tunnel.
/// 5. No duplicate tunnel processes can run concurrently.
class RemoteAccessManager extends ChangeNotifier {
  final LocalApiServer apiServer;
  final IRemoteAccessProvider _provider;

  StreamSubscription<RemoteAccessStatus>? _providerSubscription;
  VoidCallback? _apiServerListener;
  bool _isDisposed = false;
  String? _customErrorMessage;

  RemoteAccessManager({
    required this.apiServer,
    IRemoteAccessProvider? provider,
  }) : _provider = provider ?? CloudflareQuickTunnelProvider() {
    _initListeners();
  }

  void _initListeners() {
    _providerSubscription = _provider.statusStream.listen((status) {
      if (!_isDisposed) {
        _customErrorMessage = null;
        notifyListeners();
      }
    });

    // Listen to local API server lifecycle
    _apiServerListener = () {
      if (!_isDisposed) {
        // If local server stopped while tunnel was active, terminate tunnel immediately
        if (!apiServer.isRunning &&
            (_provider.status == RemoteAccessStatus.connected ||
                _provider.status == RemoteAccessStatus.starting)) {
          stopRemoteAccess();
        }
        notifyListeners();
      }
    };
    apiServer.addListener(_apiServerListener!);
  }

  IRemoteAccessProvider get provider => _provider;
  RemoteAccessStatus get status => _provider.status;
  bool get isConnected => _provider.status == RemoteAccessStatus.connected;
  bool get isStarting => _provider.status == RemoteAccessStatus.starting;
  bool get isStopping => _provider.status == RemoteAccessStatus.stopping;
  bool get isDisabled => _provider.status == RemoteAccessStatus.disabled;
  bool get hasError => _provider.status == RemoteAccessStatus.error;

  String? get publicHttpsUrl => _provider.publicHttpsUrl;
  String? get errorMessage => _customErrorMessage ?? _provider.errorMessage;
  String get providerName => _provider.name;
  String get providerDescription => _provider.description;

  Future<bool> checkPrerequisites() => _provider.checkPrerequisites();

  /// Starts the remote access tunnel pointing to the running local API server.
  ///
  /// Fails safely if the local server is not currently running.
  Future<bool> startRemoteAccess() async {
    _checkNotDisposed();

    // Enforce dependency: local server must be running
    if (!apiServer.isRunning || apiServer.activePort == null) {
      _customErrorMessage = 'Local API server must be running before starting remote access. Start the server first.';
      notifyListeners();
      return false;
    }

    if (isConnected || isStarting) {
      return true;
    }

    _customErrorMessage = null;

    try {
      final assignedUrl = await _provider.startTunnel(
        localPort: apiServer.activePort!,
        localHost: apiServer.loopbackHost,
      );
      if (!_isDisposed) notifyListeners();
      return assignedUrl.isNotEmpty;
    } catch (e) {
      if (!_isDisposed) {
        _customErrorMessage =
            _provider.errorMessage ?? e.toString().split('\n').first;
        notifyListeners();
      }
      return false;
    }
  }

  /// Stops the remote access tunnel and revokes the public HTTPS endpoint.
  Future<void> stopRemoteAccess() async {
    if (_isDisposed) return;
    if (_provider.status == RemoteAccessStatus.disabled ||
        _provider.status == RemoteAccessStatus.stopping) {
      return;
    }

    try {
      await _provider.stopTunnel();
    } catch (_) {}

    if (!_isDisposed) {
      _customErrorMessage = null;
      notifyListeners();
    }
  }

  void _checkNotDisposed() {
    if (_isDisposed) {
      throw StateError('RemoteAccessManager has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    if (_apiServerListener != null) {
      apiServer.removeListener(_apiServerListener!);
    }
    _providerSubscription?.cancel();
    _provider.dispose();
    super.dispose();
  }
}
