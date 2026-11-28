import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/janelas/janela_player.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';

const _link = 'http://h/live/UTILIZADOR/SEGREDO/1.ts';
final _lista = Lista(id: '1', ordem: 1, conta: Conta('x', Tipo.m3u, 'http://h/l.m3u'));
const _canais = [Canal(id: '1', nome: 'RTP 1', grupo: 'g', url: _link, numero: 101)];

/// Lê as linhas que chegam ao socket durante `d` (ou até fechar).
Future<(List<String>, bool)> _escutar(Socket s, Duration d) async {
  final linhas = <String>[];
  var fechou = false;
  final fim = Completer<void>();
  void acabar() {
    fechou = true;
    if (!fim.isCompleted) fim.complete();
  }

  s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(linhas.add,
      onDone: acabar, onError: (_) => acabar());
  await Future.any([fim.future, Future<void>.delayed(d)]);
  return (linhas, fechou);
}

void main() {
  late JanelaPlayer janela;
  int? porta;
  String? token;
  setUp(() async {
    porta = token = null;
    janela = JanelaPlayer.paraTestes((p, t) async {
      porta = p;
      token = t;
    });
    await janela.mostrar(_lista, _canais, 0);
  });
  tearDown(() => janela.fechar());

  test('I2: o player recebe um token aleatório (não vai no argv)', () {
    expect(token, isNotNull);
    expect(base64Url.decode(token!), hasLength(32));
  });

  test('I2: um processo sem token não recebe canais nem links e é desligado', () async {
    final intruso = await Socket.connect(InternetAddress.loopbackIPv4, porta!);
    intruso.write('${jsonEncode({'tipo': 'fonte', 'pedido': 1, 'i': 0})}\n');
    final (linhas, fechou) = await _escutar(intruso, const Duration(seconds: 4));
    intruso.destroy();
    expect(linhas.join(), isNot(contains('SEGREDO')));
    expect(linhas, isEmpty);
    expect(fechou, isTrue);
  });

  test('I2: quem não diz nada em 2 s é desligado', () async {
    final calado = await Socket.connect(InternetAddress.loopbackIPv4, porta!);
    final (linhas, fechou) = await _escutar(calado, const Duration(seconds: 4));
    calado.destroy();
    expect(linhas, isEmpty);
    expect(fechou, isTrue);
  });

  test('I2: uma linha sem fim (mais de 1 MB) desliga o socket', () async {
    final s = await Socket.connect(InternetAddress.loopbackIPv4, porta!);
    final escuta = _escutar(s, const Duration(seconds: 1));
    s.add(List.filled(2 * 1024 * 1024, 0x61));
    final (_, fechou) = await escuta;
    s.destroy();
    expect(fechou, isTrue);
  });

  test('I2: o player com o token fica; uma 2.ª ligação não o substitui', () async {
    final fechada = Completer<void>();
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {
      if (!fechada.isCompleted) fechada.complete();
    });
    final abertura = await l.aberturas.stream.first.timeout(const Duration(seconds: 5));
    expect(abertura.canais.single.nome, 'RTP 1');
    expect(abertura.canais.single.numero, 101, reason: 'o número do portal chega à janela do player');
    expect((await l.fonte(0)).url, _link);

    // depois de o player entrar, a principal deixa de aceitar ligações
    try {
      final outro = await Socket.connect(InternetAddress.loopbackIPv4, porta!);
      outro.write('${jsonEncode({'tipo': 'ola', 'token': token})}\n');
      outro.write('${jsonEncode({'tipo': 'fonte', 'pedido': 1, 'i': 0})}\n');
      final (linhas, _) = await _escutar(outro, const Duration(seconds: 3));
      outro.destroy();
      expect(linhas.join(), isNot(contains('SEGREDO')));
    } on SocketException {
      // recusada: é o esperado
    }
    expect(fechada.isCompleted, isFalse, reason: 'o player verdadeiro não pode ser desligado');
    expect((await l.fonte(0)).url, _link);
  });

  test('a janela do player pede o programa a dar e o seguinte à principal (o guia está lá)', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    await l.aberturas.stream.first.timeout(const Duration(seconds: 5));
    // sem guia: nada
    expect(await l.programas(0), (null, null));
    final pedidos = <String>[];
    await janela.mostrar(_lista, _canais, 0, programasDe: (c) async {
      pedidos.add(c.nome);
      return (const Programa(100, 200, 'Telejornal', 'As notícias'), const Programa(200, 300, 'Prós e Contras'));
    });
    final (atual, seguinte) = await l.programas(0);
    expect(atual, const Programa(100, 200, 'Telejornal', 'As notícias'));
    expect(seguinte, const Programa(200, 300, 'Prós e Contras'));
    expect(pedidos, ['RTP 1']);
    // um índice que não existe: nada (e a ligação continua)
    expect(await l.programas(7), (null, null));
    expect((await l.fonte(0)).url, _link);
  });

  test('a 1.ª abertura não se perde se a janela do player só a escuta depois (preferências, runApp)', () async {
    final l = await LigacaoPrincipal.ligar(porta!, token: token!, aoFechar: () {});
    // a principal manda a abertura logo a seguir ao "ola"; a janela do player ainda está a
    // ler as preferências e a montar a app quando ela chega
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final aberturas = StreamIterator(l.aberturas.stream);
    expect(await aberturas.moveNext().timeout(const Duration(seconds: 5), onTimeout: () => false), isTrue,
        reason: 'sem a abertura a janela do player fica para sempre na rodinha');
    expect(aberturas.current.canais.single.nome, 'RTP 1');

    // as seguintes (trocar de canal na principal) continuam a chegar
    await janela.mostrar(_lista, const [Canal(id: '2', nome: 'SIC', grupo: 'g')], 0);
    expect(await aberturas.moveNext().timeout(const Duration(seconds: 5), onTimeout: () => false), isTrue);
    expect(aberturas.current.canais.single.nome, 'SIC');
    await aberturas.cancel();
  });

  group('_aLancar', () {
    test('se lançar o player falha, o erro chega a quem pediu e o próximo pedido tenta de novo', () async {
      var vezes = 0;
      final j = JanelaPlayer.paraTestes((p, t) async {
        vezes++;
        if (vezes == 1) throw const ProcessException('player.exe', [], 'não encontrado');
      });
      addTearDown(j.fechar);
      await expectLater(j.mostrar(_lista, _canais, 0), throwsA(isA<ErroLista>()));
      await j.mostrar(_lista, _canais, 0);
      expect(vezes, 2, reason: 'depois de uma falha o player tem de voltar a poder abrir');
    });

    test('se a janela não liga a tempo, avisa e o próximo pedido tenta de novo', () async {
      var vezes = 0;
      final j = JanelaPlayer.paraTestes((p, t) async => vezes++, prazo: const Duration(milliseconds: 200));
      addTearDown(j.fechar);
      final avisos = <String>[];
      await j.mostrar(_lista, _canais, 0, aoFalhar: avisos.add);
      await j.mostrar(_lista, _canais, 0, aoFalhar: avisos.add); // ainda a abrir: não lança outra
      expect(vezes, 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(avisos, ['A janela do player não abriu a tempo. Tente de novo.']);
      await j.mostrar(_lista, _canais, 0);
      expect(vezes, 2);
    });
  });
}
