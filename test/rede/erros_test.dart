import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/protocolos/stalker.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';

const mac = '00:1A:79:12:34:56';
const segredo = 'http://h:8080/player_api.php?username=U&password=P';

void _semSegredos(String t) {
  expect(t, isNot(contains('http')));
  expect(t, isNot(contains('password')));
  expect(t, isNot(contains('00:1A:79')));
  expect(t, isNot(contains('uri =')));
  expect(t, isNotEmpty);
}

void main() {
  group('I1: descreverErro nunca mostra links nem MACs', () {
    test('I1: HttpException sem o uri', () {
      final t = descreverErro(HttpException('Connection closed', uri: Uri.parse('http://h/c/portal.php?mac=$mac')));
      _semSegredos(t);
      expect(t, isNot(contains('Connection')), reason: 'texto em português, não o inglês do dart:io');
    });
    test('I1: TLS / handshake', () {
      _semSegredos(descreverErro(const HandshakeException('CERTIFICATE_VERIFY_FAILED $segredo')));
      expect(descreverErro(const TlsException('x')), contains('segura'));
    });
    test('I1: FormatException de Uri.parse com o URL', () {
      Object? erro;
      try {
        Uri.parse('http://[x/$segredo');
      } catch (e) {
        erro = e;
      }
      _semSegredos(descreverErro(erro!));
    });
    test('I1: SocketException e outros', () {
      _semSegredos(descreverErro(SocketException('Connection refused', address: InternetAddress.loopbackIPv4)));
      _semSegredos(descreverErro(StateError('falhou com $segredo e mac=$mac')));
      _semSegredos(descreverErro(Exception(segredo)));
      expect(descreverErro(ErroLista('portal não encontrado')), 'portal não encontrado');
      expect(descreverErro(TimeoutException('x')), 'o servidor não respondeu a tempo');
    });
    test('I1: semSegredos tira links e MACs de um texto', () {
      expect(semSegredos('falhou $segredo com mac=$mac.'), isNot(contains('U&password')));
      expect(semSegredos('MAC 00:1a:79:ab:cd:ef'), isNot(contains('00:1a')));
    });
    test('I1: classificarFalha (motivo guardado) sem segredos', () {
      _semSegredos(classificarFalha(HttpException('Connection closed', uri: Uri.parse(segredo))).motivo);
      _semSegredos(classificarFalha(StateError('x $segredo')).motivo);
    });
  });

  test('I1: portal que corta a ligação: a mensagem do Stalker não leva o link com o MAC', () async {
    final srv = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    srv.listen((s) => s.destroy());
    try {
      final c = Conta('x', Tipo.stalker, 'http://127.0.0.1:${srv.port}/c/', mac: mac);
      Object? erro;
      try {
        await Stalker().abrir(c);
      } catch (e) {
        erro = e;
      }
      expect(erro, isA<ErroLista>());
      _semSegredos((erro as ErroLista).mensagem);
      _semSegredos(descreverErro(erro));
    } finally {
      await srv.close();
    }
  });
}
