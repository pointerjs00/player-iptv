import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/licencas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('os textos da GPLv3 e da LGPLv2.1 e o aviso do libmpv vão na app (página de licenças)', () async {
    registarLicencasLibmpv();
    final textos = <String>[];
    await for (final l in LicenseRegistry.licenses) {
      if (l.packages.contains(pacoteLicencasLibmpv)) {
        textos.add(l.paragraphs.map((p) => p.text).join('\n'));
      }
    }
    final tudo = textos.join('\n');
    expect(tudo, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(tudo, contains('Version 3, 29 June 2007'));
    expect(tudo, contains('GNU LESSER GENERAL PUBLIC LICENSE'));
    expect(tudo, contains('Version 2.1, February 1999'));
    expect(tudo, contains('--enable-gpl --enable-version3'));
    expect(tudo, contains('libavdevice'));
    expect(tudo, isNot(contains('biblioteca dinâmica')));
  });
}
