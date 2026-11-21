import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

Importada _imp(String linha, [UltimaVerificacao? u]) => Importada(contaDeLinha(linha)!, u);

void main() {
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('bib'));
  tearDown(() async => pasta.delete(recursive: true));

  test('repetidas não duplicam e o resultado mais recente fica', () async {
    final b = await Biblioteca.abrir(pasta);
    final velho = UltimaVerificacao(estado: 'nao_funciona', data: DateTime(2026, 1, 1));
    final novo = UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 2, 1), validade: '2027-10-16');
    expect(await b.adicionar([_imp('http://nxtbox.uk/c/ 00:1A:79:00:00:01', velho)]), 1);
    expect(await b.adicionar([_imp('http://NXTBOX.uk:80 00:1a:79:00:00:01', novo),
        _imp('http://outro.com/c/ 00:1A:79:00:00:01')]), 1);
    expect(b.listas, hasLength(2));
    expect(b.listas.first.ultima!.estado, 'funciona');
    expect(b.listas.first.nome, '001NXTBOX 161027');
    // um resultado mais antigo não substitui
    await b.adicionar([_imp('http://nxtbox.uk 00:1A:79:00:00:01', velho)]);
    expect(b.listas.first.ultima!.estado, 'funciona');
  });

  test('a ordem não muda ao apagar outras e tudo persiste', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01'), _imp('http://b.com/c/ 00:1A:79:00:00:01'),
        _imp('http://c.com/c/ 00:1A:79:00:00:01')]);
    await b.remover(b.listas[1].id);
    await b.alternarFavorito(b.listas[0].id, 'canal-1');
    await b.registarVerificacao(b.listas[1].id,
        UltimaVerificacao(estado: 'inconclusivo', data: DateTime(2026, 3, 1)));
    final r = await Biblioteca.abrir(pasta);
    expect(r.listas.map((l) => l.nomeMostrado), ['001A', 'INC 003C']);
    expect(r.listas.first.favoritos, {'canal-1'});
    await r.adicionar([_imp('http://d.com/c/ 00:1A:79:00:00:01')]);
    expect(r.listas.last.nome, '004D');
  });

  test('gravações ao mesmo tempo não se atropelam', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([for (var i = 0; i < 20; i++) _imp('http://h$i.com/c/ 00:1A:79:00:00:01')]);
    await Future.wait([
      for (final l in b.listas)
        b.registarVerificacao(l.id, UltimaVerificacao(estado: 'funciona', data: DateTime(2026))),
    ]);
    final r = await Biblioteca.abrir(pasta);
    expect(r.listas.where((l) => l.ultima?.estado == 'funciona'), hasLength(20));
  });

  test('ficheiro estragado: começa vazia e guarda uma cópia', () async {
    await File('${pasta.path}/biblioteca.json').writeAsString('{estragado');
    final b = await Biblioteca.abrir(pasta);
    expect(b.listas, isEmpty);
    expect(await File('${pasta.path}/biblioteca.json.bak').exists(), isTrue);
  });

  Canal canalN(int n) => Canal(id: 'c$n', nome: 'Canal $n', grupo: 'G');

  test('vistos há pouco: 20 no máximo, mais recente primeiro, sem repetidos, e persistem', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
    final id = b.listas.single.id;
    for (var i = 1; i <= 25; i++) {
      await b.registarVisto(id, canalN(i));
    }
    expect(b.listas.single.vistos, [for (var i = 25; i > 5; i--) 'c$i']);
    // rever um canal antigo passa-o para a frente, sem o repetir
    await b.registarVisto(id, canalN(10));
    expect(b.listas.single.vistos.first, 'c10');
    expect(b.listas.single.vistos.where((v) => v == 'c10'), hasLength(1));
    expect(b.listas.single.vistos, hasLength(20));
    // o mesmo canal outra vez (já à frente) não muda nada
    await b.registarVisto(id, canalN(10));
    expect(b.listas.single.vistos.first, 'c10');
    final r = await Biblioteca.abrir(pasta);
    expect(r.listas.single.vistos, b.listas.single.vistos);
  });

  test('JSON antigo sem "vistos" abre com a lista vazia', () {
    final l = Lista.deJson({
      'id': 'x', 'ordem': 1, 'conta': contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!.paraJson(),
    })!;
    expect(l.vistos, isEmpty);
    expect(l.paraJson().containsKey('vistos'), isFalse);
  });

  test('lista favorita: guarda e relê; JSON antigo sem o campo é false', () async {
    var b = await Biblioteca.abrir(pasta);
    await b.adicionar([_imp('http://a.com/l.m3u'), _imp('http://b.com/l.m3u')]);
    final id = b.listas.first.id;
    expect(b.listas.first.favorita, isFalse);
    await b.alternarFavorita(id);
    b = await Biblioteca.abrir(pasta);
    expect(b.porId(id)!.favorita, isTrue);
    expect(b.listas.where((l) => l.favorita), hasLength(1));
    await b.alternarFavorita(id);
    b = await Biblioteca.abrir(pasta);
    expect(b.porId(id)!.favorita, isFalse);
    final antiga = Lista.deJson({
      'id': 'x', 'ordem': 1, 'conta': contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!.paraJson(),
    })!;
    expect(antiga.favorita, isFalse);
    expect(antiga.paraJson().containsKey('favorita'), isFalse);
  });

  test('a lista favorita passa pela cópia de segurança (juntar e substituir)', () {
    final conta = contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!;
    final atual = Lista(id: 'a', ordem: 1, conta: conta);
    final ficheiro = Lista(id: 'f', ordem: 1, conta: conta, favorita: true);
    expect(planearRestauro([atual], [ficheiro], substituir: true).listas.single.favorita, isTrue);
    expect(planearRestauro([atual], [ficheiro], substituir: false).listas.single.favorita, isTrue);
    final jaFavorita = Lista(id: 'a', ordem: 1, conta: conta, favorita: true);
    expect(planearRestauro([jaFavorita], [Lista(id: 'f', ordem: 1, conta: conta)], substituir: false)
        .listas.single.favorita, isTrue);
  });

  test('vistos passam pela cópia de segurança (juntar e substituir)', () {
    final conta = contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!;
    final atual = Lista(id: 'a', ordem: 1, conta: conta);
    final ficheiro = Lista(id: 'f', ordem: 1, conta: conta, vistos: ['c2', 'c1']);
    expect(planearRestauro([atual], [ficheiro], substituir: true).listas.single.vistos, ['c2', 'c1']);
    expect(planearRestauro([atual], [ficheiro], substituir: false).listas.single.vistos, ['c2', 'c1']);
    final comVistos = Lista(id: 'a', ordem: 1, conta: conta, vistos: ['c9']);
    expect(planearRestauro([comVistos], [ficheiro], substituir: false).listas.single.vistos, ['c9']);
  });

  test('receber do Gestor mantém os vistos de uma lista que já existe', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([_imp('http://a.com/c/ 00:1A:79:00:00:01')]);
    final id = b.listas.single.id;
    await b.registarVisto(id, canalN(1));
    final doGestor = Lista(
        id: 'g', ordem: 7, conta: contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!,
        ultima: UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 5, 1)));
    await b.receber([doGestor], ModoEnvio.adicionar);
    expect(b.listas.single.ultima!.estado, 'funciona');
    expect(b.listas.single.vistos, ['c1']);
    final r = await Biblioteca.abrir(pasta);
    expect(r.listas.single.vistos, ['c1']);
  });

  test('cache de canais', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([_imp('http://a.com/x.m3u')]);
    final id = b.listas.single.id;
    expect(await b.canaisEmCache(id), isNull);
    await b.guardarCanais(id, ConteudoLista(['G'], [const Canal(id: '1', nome: 'RTP 1', grupo: 'G', url: 'u')]));
    expect((await b.canaisEmCache(id))!.canais.single.nome, 'RTP 1');
    await b.remover(id);
    expect(await b.canaisEmCache(id), isNull);
  });
}
