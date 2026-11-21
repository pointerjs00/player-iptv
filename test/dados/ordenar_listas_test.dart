import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';

Lista _l(int ordem, String nome, {String? estado, DateTime? data, String validade = '', bool favorita = false}) =>
    Lista(
      id: '$ordem',
      ordem: ordem,
      conta: contaDeLinha('http://h$ordem.com/l.m3u')!,
      nomeProprio: nome,
      favorita: favorita,
      ultima: estado == null
          ? null
          : UltimaVerificacao(estado: estado, data: data ?? DateTime(2026), validade: validade),
    );

List<String> _nomes(List<Lista> l) => [for (final x in l) x.nome];

void main() {
  final listas = [
    _l(1, 'Zeta', estado: 'nao_funciona', data: DateTime(2026, 11, 1), validade: '2027-01-01'),
    _l(2, 'alfa', estado: 'funciona', data: DateTime(2026, 11, 3), validade: 'sem limite'),
    _l(3, 'Ébano'),
    _l(4, 'Beta', estado: 'inconclusivo', data: DateTime(2026, 11, 2), validade: '2026-12-01'),
  ];

  test('cada ordem', () {
    expect(_nomes(ordenarListas(listas, OrdemListas.adicao)), ['Zeta', 'alfa', 'Ébano', 'Beta']);
    expect(_nomes(ordenarListas(listas, OrdemListas.nome)), ['alfa', 'Beta', 'Ébano', 'Zeta']);
    expect(_nomes(ordenarListas(listas, OrdemListas.estado)), ['alfa', 'Beta', 'Zeta', 'Ébano']);
    expect(_nomes(ordenarListas(listas, OrdemListas.verificacao)), ['alfa', 'Beta', 'Zeta', 'Ébano']);
    expect(_nomes(ordenarListas(listas, OrdemListas.validade)), ['alfa', 'Zeta', 'Beta', 'Ébano']);
  });

  test('as favoritas vêm sempre à frente, entre elas pela mesma ordem', () {
    final comFav = [...listas, _l(5, 'Delta', favorita: true), _l(6, 'Caixa', favorita: true)];
    expect(_nomes(ordenarListas(comFav, OrdemListas.nome)), ['Caixa', 'Delta', 'alfa', 'Beta', 'Ébano', 'Zeta']);
    expect(_nomes(ordenarListas(comFav, OrdemListas.adicao)).take(2), ['Delta', 'Caixa']);
  });

  test('a ordem escolhida grava-se e volta a ler-se', () async {
    final pasta = Directory.systemTemp.createTempSync('ordem-listas');
    addTearDown(() => pasta.deleteSync(recursive: true));
    final b = await Biblioteca.abrir(pasta);
    expect(b.ordemListas, OrdemListas.adicao);
    await b.definirOrdemListas(OrdemListas.nome);
    expect((await Biblioteca.abrir(pasta)).ordemListas, OrdemListas.nome);
  });
}
