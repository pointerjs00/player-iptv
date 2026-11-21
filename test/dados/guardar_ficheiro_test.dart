
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/guardar_ficheiro.dart';

class _Falso implements DestinoTransferencias {
  _Falso(this.ja, {this.falha, this.renomeado});
  final String? renomeado;
  final List<String> ja;
  final Object? falha;
  String? escrito;
  @override
  Future<List<String>> existentes() async => ja;
  @override
  Future<String> escrever(String nome, Uint8List bytes, String mimeType) async {
    if (falha != null) throw falha!;
    escrito = nome;
    return renomeado ?? nome;
  }
}

void main() {
  group('nomeSemColisao', () {
    test('livre mantém o nome', () => expect(nomeSemColisao('Accounts.json', ['x.json']), 'Accounts.json'));
    test('colisão -> (2)', () => expect(nomeSemColisao('Accounts.json', ['Accounts.json']), 'Accounts (2).json'));
    test('salta os já usados', () {
      expect(nomeSemColisao('Accounts.json', ['Accounts.json', 'Accounts (2).json']), 'Accounts (3).json');
    });
    test('sem extensão', () => expect(nomeSemColisao('copia', ['copia']), 'copia (2)'));
  });

  group('guardarFicheiro (Android)', () {
    test('escolhe nome livre e devolve o destino', () async {
      final d = _Falso(['Accounts.json']);
      final r = await guardarFicheiro('Accounts.json', Uint8List(1), 'application/json', destino: d, android: true);
      expect(d.escrito, 'Accounts (2).json');
      expect(r.destino, 'Transferências/Accounts (2).json');
      expect(r.cancelado, false);
    });
    test('o Android renomeou -> mostra o nome real devolvido', () async {
      final d = _Falso([], renomeado: 'Accounts (3).json');
      final r = await guardarFicheiro('Accounts.json', Uint8List(1), 'application/json', destino: d, android: true);
      expect(r.destino, 'Transferências/Accounts (3).json');
    });
    test('falha -> ErroGuardar com mensagem', () async {
      final d = _Falso([], falha: PlatformException(code: 'io', message: 'disco cheio'));
      expect(
        guardarFicheiro('a.json', Uint8List(1), 'application/json', destino: d, android: true),
        throwsA(isA<ErroGuardar>().having((e) => e.mensagem, 'mensagem', contains('disco cheio'))),
      );
    });
    test('permissão negada -> mensagem própria', () async {
      final d = _Falso([], falha: PlatformException(code: 'permissao'));
      expect(
        guardarFicheiro('a.json', Uint8List(1), 'application/json', destino: d, android: true),
        throwsA(isA<ErroGuardar>().having((e) => e.mensagem, 'm', contains('permissão'))),
      );
    });
  });
}
