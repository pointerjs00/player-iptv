import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/desporto/indice_canais.dart';
import 'package:player_iptv/desporto/modelo.dart';
import 'package:player_iptv/desporto/onde_ver.dart';
import 'package:player_iptv/desporto/preferencias_jogos.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

/// O índice dos canais portugueses das listas e a ordem das fontes no «Onde ver» (spec §8;
/// Review Focus 2 e 5).
void main() {
  late Directory pasta;
  late Biblioteca bib;
  late PreferenciasJogos prefs;

  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('indice');
    bib = await Biblioteca.abrir(pasta);
    prefs = await PreferenciasJogos.abrir(Directory('${pasta.path}/desporto'));
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  final agora = DateTime.utc(2026, 11, 27, 12);
  UltimaVerificacao verificacao(String estado, int horas) =>
      UltimaVerificacao(estado: estado, validade: '2027-01-01', data: agora.subtract(Duration(hours: horas)));

  /// Três listas: A funciona (verificada há 5 h), B funciona (há 1 h), C não funciona.
  Future<(Lista, Lista, Lista)> tres() async {
    await bib.adicionar([
      Importada(contaDeLinha('http://a.com/l.m3u')!, verificacao('funciona', 5)),
      Importada(contaDeLinha('http://b.com/l.m3u')!, verificacao('funciona', 1)),
      Importada(contaDeLinha('http://c.com/l.m3u')!, verificacao('nao_funciona', 1)),
    ]);
    final [a, b, c] = bib.listas;
    await bib.guardarCanais(a.id, ConteudoLista(['|PT| DESPORTO', '|BR| ESPORTES', 'ESPAÑA'], const [
      Canal(id: 'a1', nome: '|PT| SPORT TV 1 FHD', grupo: '|PT| DESPORTO'),
      Canal(id: 'a2', nome: '|BR| SPORTV 1', grupo: '|BR| ESPORTES'),
      Canal(id: 'a3', nome: 'DAZN 1', grupo: 'ESPAÑA'),
      Canal(id: 'a4', nome: 'DAZN 1 PT', grupo: '|PT| DESPORTO'),
    ]));
    await bib.guardarCanais(b.id, ConteudoLista(['PT'], const [
      Canal(id: 'b1', nome: 'PT: SPORTTV1 4K', grupo: 'PT'),
      Canal(id: 'b2', nome: 'SPORT TV 1 HD', grupo: 'PT'),
    ]));
    await bib.guardarCanais(c.id, ConteudoLista(['PT'], const [Canal(id: 'c1', nome: 'SPORT TV 1', grupo: 'PT')]));
    return (a, b, c);
  }

  IndiceCanais indice() => IndiceCanais(bib, Directory('${pasta.path}/desporto'), prefs);

  test('só os canais portugueses: o SporTV brasileiro e a DAZN espanhola ficam de fora', () async {
    await tres();
    final i = indice();
    await i.atualizar();
    expect(i.fontes('sporttv1').map((f) => f.canal.id), unorderedEquals(['a1', 'b1', 'b2', 'c1']));
    expect(i.fontes('dazn1').map((f) => f.canal.id), ['a4']);
  });

  test('a ordem: a que funcionou da última vez, as que funcionam (verificação mais recente), e as que não', () async {
    final (a, b, c) = await tres();
    final i = indice();
    await i.atualizar();
    var o = ordenarFontes(i.fontes('sporttv1'), preferida: Qualidade.hd);
    expect(o.map((f) => f.canal.id), ['b2', 'b1', 'a1', 'c1'], reason: 'B (há 1 h): HD (a preferida) antes do 4K');
    prefs.registarFuncionou('sporttv1', a.id, 'a1', agora);
    o = ordenarFontes(i.fontes('sporttv1'), preferida: Qualidade.hd, ultima: prefs.ultimaFonte('sporttv1'));
    expect(o.first.canal.id, 'a1');
    expect(o.last.lista.id, c.id, reason: 'a que não funciona fica no fim');
    expect(b.id, isNotEmpty);
  });

  test('100 mil canais indexam num isolate; sem mudar a cache, não se relê', () async {
    await bib.adicionar([Importada(contaDeLinha('http://grande.com/l.m3u')!)]);
    final l = bib.listas.single;
    await bib.guardarCanais(l.id, ConteudoLista(['G'], [
      for (var k = 0; k < 100000; k++) Canal(id: 'c$k', nome: k == 77777 ? '|PT| SPORT TV 2' : 'Canal $k', grupo: 'G'),
    ]));
    final i = indice();
    await i.atualizar();
    expect(i.fontes('sporttv2').single.canal.id, 'c77777');
    final leituras = bib.leiturasCache[l.id];
    await i.atualizar();
    expect(bib.leiturasCache[l.id], leituras, reason: 'a cache não mudou');
    // outra sessão da app: o índice vem do disco
    final outro = indice();
    await outro.atualizar();
    expect(outro.fontes('sporttv2'), hasLength(1));
    expect(bib.leiturasCache[l.id], leituras);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('listas sem cache contam-se (para «Atualizar canais»)', () async {
    await tres();
    await bib.adicionar([Importada(contaDeLinha('http://sem.com/l.m3u')!)]);
    final i = indice();
    await i.atualizar();
    expect(i.listasSemCache, 1);
  });

  test('a associação manual: «não é este» tira; associar junta um canal não reconhecido', () async {
    final (a, b, _) = await tres();
    await bib.guardarCanais(b.id, ConteudoLista(['X'], const [
      Canal(id: 'b1', nome: 'PT: SPORTTV1 4K', grupo: 'PT'),
      Canal(id: 'b9', nome: 'STV UM', grupo: 'X'),
    ]));
    final i = indice();
    await i.atualizar();
    prefs.associar(a.id, const Canal(id: 'a1', nome: '|PT| SPORT TV 1 FHD', grupo: '|PT| DESPORTO'), null);
    prefs.associar(b.id, const Canal(id: 'b9', nome: 'STV UM', grupo: 'X'), 'sporttv1');
    expect(i.fontes('sporttv1').map((f) => f.canal.id), unorderedEquals(['b1', 'b9', 'c1']));
  });

  test('as preferências dos jogos ficam no disco', () async {
    prefs.registarFuncionou('btv', 'L', 'c', agora);
    prefs.qualidade = Qualidade.uhd;
    await prefs.guardar();
    final outra = await PreferenciasJogos.abrir(Directory('${pasta.path}/desporto'));
    expect(outra.ultimaFonte('btv')?.canalId, 'c');
    expect(outra.qualidade, Qualidade.uhd);
    expect(outra.competicoes, contains('liga-portugal'));
    expect(outra.competicoes, isNot(contains('taca-davis')), reason: 'desligada por omissão');
  });
}
