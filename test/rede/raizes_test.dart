import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/rede/raizes.dart';

void main() {
  test('a raiz GoDaddy TLS Root CA - R1 (a do t.me) é a certa e carrega', () {
    final der = base64.decode(raizGoDaddyR1
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join());
    expect(sha256.convert(der).toString().toUpperCase(),
        '25CF3DA8E9B97ADDBF92543C2B82527C8A4E2CFF2062A6483040D4B64ACE719F');
    // sozinha, sem as do sistema: o certificado é válido para o SecurityContext
    expect(() => SecurityContext(withTrustedRoots: false)..setTrustedCertificatesBytes(ascii.encode(raizGoDaddyR1)),
        returnsNormally);
    expect(contextoSeguro, returnsNormally);
  });
}
