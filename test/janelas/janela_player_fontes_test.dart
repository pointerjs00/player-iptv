import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/desporto/onde_ver.dart';
import 'package:player_iptv/janelas/janela_player.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

Lista _lista(String id, String host) => Lista(
    id: id, ordem: int.parse(id), conta: Conta('c$id', Tipo.xtream, 'http://$host', utilizador: 'u', password: 'p'),
    nomeProprio: 'Lista $id');

/// O mesmo id nas duas listas (acontece no Xtream): cada fonte tem de usar a sua conta.
final _fontes = [
  FonteCanal(_lista('1', 'um.invalido'), const Canal(id: '7', nome: 'SPORT TV 1', grupo: 'PT'), canalTv: 'sporttv1'),
  FonteCanal(_lista('2', 'dois.invalido'), const Canal(id: '7', nome: 'SPORT TV 1 FHD', grupo: 'Desporto'), canalTv: 'sporttv1'),
];

void main() {
  late JanelaPlayer janela;
  int? porta;
  String? token;
  final funcionou = <FonteCanal>[];
  final vistos = <FonteCanal>[];
  setUp(() async {
    porta = token = null;
    funcionou.clear();
    vistos.clear();
    janela = JanelaPlayer.paraTestes((p, t) async {
      porta = p;
      token = t;
    });
    await janela.mostrarFontes(_fontes, aoFuncionar: funcionou.add, aoVer: vistos.add);
  });
  tearDown(() => janela.fechar());

  test('a mensagem abrir leva o nome da lista de cada canal e a troca automática', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    final a = await l.aberturas.stream.first.timeout(const Duration(seconds: 5));
    expect(a.canais.map((c) => c.nome), ['SPORT TV 1', 'SPORT TV 1 FHD']);
    expect(a.listas, ['Lista 1', 'Lista 2']);
    expect(a.listaIds, ['1', '2']);
    expect(a.troca, isTrue);
    expect(a.i, 0);
  });

  test('o pedido fonte do índice 1 usa a conta da lista 1 (a 2.ª)', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    await l.aberturas.stream.first.timeout(const Duration(seconds: 5));
    final f1 = await l.fonte(1);
    expect(f1.url, startsWith('http://dois.invalido/'));
    expect(f1.url, endsWith('/7.ts'));
    expect((await l.fonte(0)).url, startsWith('http://um.invalido/'));
    expect(vistos.map((f) => f.lista.id), ['2', '1']);
  });

  test('a fonte que deu imagem chega à principal (funcionou da última vez)', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    await l.aberturas.stream.first.timeout(const Duration(seconds: 5));
    l.funcionou(1);
    for (var k = 0; k < 50 && funcionou.isEmpty; k++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(funcionou.map((f) => f.lista.id), ['2']);
  });

  test('uma abertura normal (uma lista) não traz listas por canal nem troca', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    final it = StreamIterator(l.aberturas.stream);
    expect(await it.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    await janela.mostrar(_fontes.first.lista, const [Canal(id: '1', nome: 'RTP 1', grupo: 'g')], 0);
    expect(await it.moveNext().timeout(const Duration(seconds: 5)), isTrue);
    expect(it.current.listas, isNull);
    expect(it.current.troca, isFalse);
    await it.cancel();
  });
}
