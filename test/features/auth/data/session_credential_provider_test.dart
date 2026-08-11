import 'package:flutter_template/core/network/network_credential_provider.dart';
import 'package:flutter_template/features/auth/data/session_credential_provider.dart';
import 'package:flutter_template/features/auth/domain/auth_session_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delegates every read and keeps diagnostics redacted', () async {
    final coordinator = _CredentialCoordinator();
    final provider = SessionCredentialProvider(coordinator);

    final first = await provider.loadCredential();
    final second = await provider.loadCredential();

    expect(coordinator.loadCount, 2);
    expect(first?.headerName, 'authorization');
    expect(second?.headerName, 'authorization');
    expect(provider.toString(), 'SessionCredentialProvider([REDACTED])');
    expect(provider.toString(), isNot(contains('fixture-access')));
  });
}

final class _CredentialCoordinator implements AuthSessionCoordinator {
  var loadCount = 0;

  @override
  int get sessionGeneration => 1;

  @override
  Future<NetworkCredential?> loadNetworkCredential() async {
    loadCount++;
    return NetworkCredential(
      headerName: 'authorization',
      headerValue: 'Bearer fixture-access',
    );
  }

  @override
  Future<void> refreshSession() async {}

  @override
  Future<void> invalidateSession() async {}
}
