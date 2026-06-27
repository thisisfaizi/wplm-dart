// A runnable command-line demo of the WPLM Dart SDK.
//
// Usage:
//   dart run example/wplm_example.dart <server-url> <license-key>
//
// e.g. dart run example/wplm_example.dart https://license.vendor.com ABCD-EFGH-IJKL-MNOP
//
// ignore_for_file: avoid_print
import 'package:wplm/wplm.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print(
        'Usage: dart run example/wplm_example.dart <server-url> <license-key>');
    return;
  }

  final wplm = WplmClient(
    baseUrl: args[0],
    licenseKey: args[1],
    // For production, bundle the public key so offline verification needs no
    // network at all:
    //   publicKeyBase64: 'PASTE FROM GET /wp-json/wplm/v1/public-key',
  );

  try {
    print('→ Activating this device…');
    final machine = await wplm.activate(
      name: 'CLI demo',
      platform: 'dart-cli',
      appVersion: '1.0.0',
    );
    print('  activated machine #${machine.id} (status ${machine.status})');

    print('→ Validating (offline-capable)…');
    final result = await wplm.validate(offlineOk: true);
    print('  valid=${result.valid} '
        'status=${result.license?.statusLabel} '
        'fromCache=${result.fromCache}');

    print('→ Heartbeat…');
    await wplm.heartbeat(appVersion: '1.0.0');
    print('  ok');

    print('→ Deactivating…');
    final freed = await wplm.deactivate();
    print('  deactivated=$freed');
  } on WplmRevoked {
    print('  license is revoked.');
  } on WplmLimitExceeded {
    print('  no activation seats available.');
  } on WplmNetworkError catch (e) {
    print('  network error: ${e.message}');
  } on WplmError catch (e) {
    print('  ${e.code ?? 'error'}: ${e.message}');
  } finally {
    wplm.dispose();
  }
}
