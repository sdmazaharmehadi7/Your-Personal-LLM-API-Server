import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Current status of the remote access tunnel.
enum RemoteAccessStatus { disabled, starting, connected, stopping, error }

/// Abstract interface for remote HTTPS tunnel providers.
abstract class IRemoteAccessProvider {
  String get name;
  String get description;

  RemoteAccessStatus get status;
  String? get publicHttpsUrl;
  String? get errorMessage;

  /// Checks if required CLI binaries or tools are installed on the local system.
  Future<bool> checkPrerequisites();

  /// Starts an outbound HTTPS tunnel pointing to the local host and port.
  ///
  /// Returns the assigned public HTTPS URL upon success.
  Future<String> startTunnel({
    required int localPort,
    required String localHost,
  });

  /// Stops the active tunnel and terminates any background subprocesses.
  Future<void> stopTunnel();

  /// Stream of status changes for reactive UI updates.
  Stream<RemoteAccessStatus> get statusStream;

  void dispose();
}

/// Cloudflare Quick Tunnels implementation (`cloudflared`).
///
/// Creates a temporary, zero-account HTTPS tunnel pointing to the local loopback server.
/// Uses official Cloudflare `trycloudflare.com` endpoints.
class CloudflareQuickTunnelProvider implements IRemoteAccessProvider {
  @override
  final String name = 'Cloudflare Quick Tunnels';

  @override
  final String description =
      'Free, temporary HTTPS endpoint (trycloudflare.com). No account, domain, or router port forwarding required.';

  final StreamController<RemoteAccessStatus> _statusController =
      StreamController<RemoteAccessStatus>.broadcast();

  RemoteAccessStatus _status = RemoteAccessStatus.disabled;
  String? _publicHttpsUrl;
  String? _errorMessage;
  Process? _process;
  String? _resolvedBinaryPath;

  static const List<String> _macBinarySearchPaths = [
    '/opt/homebrew/bin/cloudflared', // Apple Silicon Homebrew
    '/usr/local/bin/cloudflared', // Intel Homebrew / manual pkg
    '/usr/bin/cloudflared',
  ];

  static final RegExp _urlRegex = RegExp(
    r'https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com',
  );

  /// Validates that an extracted URL is a valid, secure HTTPS trycloudflare URL.
  /// Rejects malformed URLs, non-HTTPS protocols, and unexpected domains.
  static String? validateTunnelUrl(String line) {
    final match = _urlRegex.firstMatch(line);
    if (match == null) return null;
    final candidate = match.group(0)!;
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.scheme != 'https' ||
        !uri.host.endsWith('.trycloudflare.com') ||
        uri.hasPort) {
      return null;
    }
    return candidate;
  }

  @override
  RemoteAccessStatus get status => _status;

  @override
  String? get publicHttpsUrl => _publicHttpsUrl;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Stream<RemoteAccessStatus> get statusStream => _statusController.stream;

  @override
  Future<bool> checkPrerequisites() async {
    _resolvedBinaryPath = await _findCloudflaredBinary();
    return _resolvedBinaryPath != null;
  }

  static Future<String?> _findCloudflaredBinary() async {
    for (final path in _macBinarySearchPaths) {
      if (await File(path).exists()) {
        return path;
      }
    }

    // Check system PATH via 'which'
    try {
      final res = await Process.run('which', ['cloudflared']);
      if (res.exitCode == 0) {
        final path = res.stdout.toString().trim();
        if (path.isNotEmpty && await File(path).exists()) {
          return path;
        }
      }
    } catch (_) {}

    return null;
  }

  @override
  Future<String> startTunnel({
    required int localPort,
    required String localHost,
  }) async {
    if (_status == RemoteAccessStatus.connected && _publicHttpsUrl != null) {
      return _publicHttpsUrl!;
    }

    _setStatus(RemoteAccessStatus.starting);
    _errorMessage = null;
    _publicHttpsUrl = null;

    final binary = _resolvedBinaryPath ?? await _findCloudflaredBinary();
    if (binary == null) {
      _setStatus(RemoteAccessStatus.error);
      _errorMessage = 'cloudflared CLI not found on macOS. Install it via Homebrew: "brew install cloudflared"';
      throw StateError(_errorMessage!);
    }

    final targetUrl = 'http://$localHost:$localPort';
    final completer = Completer<String>();

    try {
      // Launch cloudflared with strict loopback target and no autoupdates
      final process = await Process.start(binary, [
        'tunnel',
        '--url',
        targetUrl,
        '--no-autoupdate',
      ], mode: ProcessStartMode.normal);

      _process = process;
      final recentStderr = <String>[];

      // Handle process termination
      unawaited(
        process.exitCode.then((code) {
          if (_status == RemoteAccessStatus.connected ||
              _status == RemoteAccessStatus.starting) {
            final detail = recentStderr.isNotEmpty
                ? recentStderr.last
                : 'exit code: $code';
            _errorMessage = 'Tunnel process terminated unexpectedly ($detail)';
            _publicHttpsUrl = null;
            _setStatus(RemoteAccessStatus.error);
            if (!completer.isCompleted) {
              completer.completeError(StateError(_errorMessage!));
            }
          }
        }),
      );

      void parseLine(String line) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          recentStderr.add(trimmed);
          if (recentStderr.length > 10) recentStderr.removeAt(0);
        }

        if (!completer.isCompleted) {
          final url = validateTunnelUrl(line);
          if (url != null) {
            _publicHttpsUrl = url;
            _setStatus(RemoteAccessStatus.connected);
            completer.complete(url);
          }
        }
      }

      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(parseLine);
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(parseLine);

      // Timeout after 30 seconds if Cloudflare fails to establish tunnel
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          stopTunnel();
          _setStatus(RemoteAccessStatus.error);
          _errorMessage = 'Cloudflare tunnel connection timed out (30s).';
          throw TimeoutException(_errorMessage);
        },
      );
    } catch (e) {
      await stopTunnel();
      _setStatus(RemoteAccessStatus.error);
      _errorMessage = e.toString().split('\n').first;
      rethrow;
    }
  }

  @override
  Future<void> stopTunnel() async {
    if (_status == RemoteAccessStatus.disabled ||
        _status == RemoteAccessStatus.stopping) {
      return;
    }

    _setStatus(RemoteAccessStatus.stopping);

    try {
      if (_process != null) {
        _process!.kill(ProcessSignal.sigterm);
        // Allow brief graceful shutdown
        await _process!.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            _process?.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        _process = null;
      }
    } catch (_) {
      try {
        _process?.kill(ProcessSignal.sigkill);
      } catch (_) {}
      _process = null;
    }

    _publicHttpsUrl = null;
    _setStatus(RemoteAccessStatus.disabled);
  }

  void _setStatus(RemoteAccessStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  @override
  void dispose() {
    stopTunnel();
    _statusController.close();
  }
}

/// In-memory mock tunnel provider for automated tests and testing without external CLI tools.
class MockRemoteAccessProvider implements IRemoteAccessProvider {
  @override
  final String name = 'Mock Remote Tunnel';

  @override
  final String description = 'Simulated tunnel provider for automated testing.';

  final StreamController<RemoteAccessStatus> _statusController =
      StreamController<RemoteAccessStatus>.broadcast();

  RemoteAccessStatus _status = RemoteAccessStatus.disabled;
  String? _publicHttpsUrl;
  String? _errorMessage;
  bool shouldFailStartup = false;
  String simulatedPublicUrl = 'https://mock-test-tunnel.trycloudflare.com';

  @override
  RemoteAccessStatus get status => _status;

  @override
  String? get publicHttpsUrl => _publicHttpsUrl;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Stream<RemoteAccessStatus> get statusStream => _statusController.stream;

  @override
  Future<bool> checkPrerequisites() async => true;

  @override
  Future<String> startTunnel({
    required int localPort,
    required String localHost,
  }) async {
    if (_status == RemoteAccessStatus.connected && _publicHttpsUrl != null) {
      return _publicHttpsUrl!;
    }

    _setStatus(RemoteAccessStatus.starting);
    _errorMessage = null;

    if (shouldFailStartup) {
      _setStatus(RemoteAccessStatus.error);
      _errorMessage = 'Simulated tunnel startup failure.';
      throw StateError(_errorMessage!);
    }

    _publicHttpsUrl = simulatedPublicUrl;
    _setStatus(RemoteAccessStatus.connected);
    return _publicHttpsUrl!;
  }

  @override
  Future<void> stopTunnel() async {
    if (_status == RemoteAccessStatus.disabled) return;
    _setStatus(RemoteAccessStatus.stopping);
    _publicHttpsUrl = null;
    _setStatus(RemoteAccessStatus.disabled);
  }

  /// Simulates unexpected tunnel termination from the provider side.
  void simulateUnexpectedDisconnect(String reason) {
    _publicHttpsUrl = null;
    _errorMessage = reason;
    _setStatus(RemoteAccessStatus.error);
  }

  void _setStatus(RemoteAccessStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  @override
  void dispose() {
    stopTunnel();
    _statusController.close();
  }
}
