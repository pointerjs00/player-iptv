import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';

/// Task 8: editar uma lista do Player (nome próprio, endereço, MAC, utilizador, password).
void main() {
  late Directory pasta;
  setUp(() async => pasta = await Directory.systemTemp.createTemp('bibed'));
  tearDown(() async => pasta.delete(recursive: true));

  final canais = ConteudoLista(['G'], const [Canal(id: '1', nome: 'RTP 1', grupo: 'G', url: 'u')]);
  final u = UltimaVerificacao(estado: 'funciona', data: DateTime(2026, 3, 1), validade: '2027-10-16');

  test('nome próprio: substitui NNNHOST DDMMAA; vazio volta ao nome gerado; persiste', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!, u)]);
    final l = b.listas.single;
    await b.editar(l.id, l.conta, nomeProprio: '  Sala  ');
    expect(b.listas.single.nome, 'Sala');
    expect((await Biblioteca.abrir(pasta)).listas.single.nome, 'Sala');
    await b.editar(l.id, l.conta, nomeProprio: '');
    expect(b.listas.single.nome, '001NXTBOX 161027');
    expect((await Biblioteca.abrir(pasta)).listas.single.nome, '001NXTBOX 161027');
  });

  test('a mesma chave (só a password mudou) mantém a cache e o resultado', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([Importada(Conta('', Tipo.xtream, 'http://h.com:8080', utilizador: 'u', password: 'p'), u)]);
    final l = b.listas.single;
    await b.guardarCanais(l.id, canais);
    final mantida = await b.editar(l.id, Conta('', Tipo.xtream, 'http://h.com:8080', utilizador: 'u', password: 'nova'));
    expect(mantida, isTrue);
    expect(b.listas.single.conta.password, 'nova');
    expect(b.listas.single.ultima, isNotNull);
    expect(await b.canaisEmCache(l.id), isNotNull);
    final r = await Biblioteca.abrir(pasta);
    expect(r.listas.single.conta.password, 'nova');
    expect(r.listas.single.id, l.id);
  });

  test('a chave muda: a cache e o resultado antigo saem (a conta é outra)', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([Importada(contaDeLinha('http://a.com/c/ 00:1A:79:00:00:01')!, u)]);
    final l = b.listas.single;
    await b.guardarCanais(l.id, canais);
    final mantida = await b.editar(l.id, Conta('', Tipo.stalker, 'http://b.com/c/', mac: '00:1A:79:00:00:02'));
    expect(mantida, isFalse);
    expect(await b.canaisEmCache(l.id), isNull);
    expect(b.listas.single.ultima, isNull);
    expect(b.listas.single.nome, '001B');
    expect(chave(b.listas.single.conta), chave(Conta('', Tipo.stalker, 'http://b.com/c/', mac: '00:1A:79:00:00:02')));
  });

  test('a chave de outra lista que já existe: recusa e nada muda', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([
      Importada(contaDeLinha('http://a.com/l.m3u')!),
      Importada(contaDeLinha('http://b.com/l.m3u')!),
    ]);
    final l = b.listas.first;
    await expectLater(b.editar(l.id, contaDeLinha('http://b.com/l.m3u')!), throwsA(isA<ErroEdicao>()));
    expect(b.listas.first.conta.endereco, 'http://a.com/l.m3u');
  });

  test('a data da cache de canais (para "da cache · há X")', () async {
    final b = await Biblioteca.abrir(pasta);
    await b.adicionar([Importada(contaDeLinha('http://a.com/l.m3u')!)]);
    final id = b.listas.single.id;
    expect(await b.dataCache(id), isNull);
    final antes = DateTime.now().subtract(const Duration(seconds: 5));
    await b.guardarCanais(id, canais);
    expect((await b.dataCache(id))!.isAfter(antes), isTrue);
  });
}
