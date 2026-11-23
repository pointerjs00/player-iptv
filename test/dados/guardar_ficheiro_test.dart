
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

  group('guardarFicheiro (Android TV: direto para Transferências)', () {
    test('escolhe nome livre e devolve o destino', () async {
      final d = _Falso(['Accounts.json']);
      final r = await guardarFicheiro('Accounts.json', Uint8List(1), 'application/json', destino: d, android: true, tv: true);
      expect(d.escrito, 'Accounts (2).json');
      expect(r.destino, 'Transferências/Accounts (2).json');
      expect(r.cancelado, false);
    });
    test('o Android renomeou -> mostra o nome real devolvido', () async {
      final d = _Falso([], renomeado: 'Accounts (3).json');
      final r = await guardarFicheiro('Accounts.json', Uint8List(1), 'application/json', destino: d, android: true, tv: true);
      expect(r.destino, 'Transferências/Accounts (3).json');
    });
    test('falha -> ErroGuardar com mensagem', () async {
      final d = _Falso([], falha: PlatformException(code: 'io', message: 'disco cheio'));
      expect(
        guardarFicheiro('a.json', Uint8List(1), 'application/json', destino: d, android: true, tv: true),
        throwsA(isA<ErroGuardar>().having((e) => e.mensagem, 'mensagem', contains('disco cheio'))),
      );
    });
    test('permissão negada -> mensagem própria', () async {
      final d = _Falso([], falha: PlatformException(code: 'permissao'));
      expect(
        guardarFicheiro('a.json', Uint8List(1), 'application/json', destino: d, android: true, tv: true),
        throwsA(isA<ErroGuardar>().having((e) => e.mensagem, 'm', contains('permissão'))),
      );
    });
  });

  group('guardarFicheiro (telemóvel Android e Windows: "Guardar como")', () {
    test('escolhe-se a pasta: mostra o caminho legível, sem tocar em Transferências', () async {
      final d = _Falso([]);
      String? pedido;
      final r = await guardarFicheiro('Accounts.json', Uint8List(1), 'application/json', destino: d, android: true,
          guardarComo: (nome, bytes, mime) async {
        pedido = nome;
        return Uri.parse(
            'content://com.android.externalstorage.documents/document/primary%3ADocuments%2FIPTV%2FAccounts.json');
      });
      expect(pedido, 'Accounts.json');
      expect(r.cancelado, false);
      expect(r.destino, 'Documents/IPTV/Accounts.json');
      expect(d.escrito, isNull, reason: 'não grava em Transferências');
    });

    test('fechar a janela é cancelar', () async {
      final r = await guardarFicheiro('a.json', Uint8List(1), 'application/json',
          android: true, guardarComo: (n, b, m) async => null);
      expect(r.cancelado, true);
    });

    test('uma falha da janela dá ErroGuardar com a mensagem', () async {
      expect(
        guardarFicheiro('a.json', Uint8List(1), 'application/json',
            android: true, guardarComo: (n, b, m) async => throw PlatformException(code: 'io', message: 'sem espaço')),
        throwsA(isA<ErroGuardar>().having((e) => e.mensagem, 'm', contains('sem espaço'))),
      );
    });
  });

  test('destinoLegivel: um content sem ":" fica com o nome do ficheiro', () {
    expect(destinoLegivel(Uri.parse('content://media/external/downloads/Accounts.json')), 'Accounts.json');
  });
}
