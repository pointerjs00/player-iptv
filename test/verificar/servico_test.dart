import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// Verificador falso: cada lista espera que o teste a solte (por endereço) e regista quem
/// começou. Com `ignorarCancelamento` devolve o resultado mesmo depois de cancelada.
class _Falso extends Verificador {
  _Falso({this.ignorarCancelamento = false}) : super(pausaReteste: Duration.zero);
  final bool ignorarCancelamento;
  final comecadas = <String>[];
  final _portas = <String, Completer<void>>{};

  Completer<void> porta(String endereco) => _portas.putIfAbsent(endereco, Completer<void>.new);
  void soltar(String endereco) {
    if (!porta(endereco).isCompleted) porta(endereco).complete();
  }

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    comecadas.add(conta.endereco);
    if (ignorarCancelamento) {
      await porta(conta.endereco).future;
    } else {
      await Future.any([porta(conta.endereco).future, _quandoCancelado(cancelamento)]);
      cancelamento?.verificar();
    }
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}

Future<void> _quandoCancelado(Cancelamento? can) async {
  while (!(can?.cancelado ?? false)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> _dar([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late Directory pasta;
  late Biblioteca bib;
  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('servico');
    bib = await Biblioteca.abrir(pasta);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  /// Listas Stalker em servidores diferentes, cada uma com o seu MAC (ou o mesmo, com `mac`).
  Future<List<Lista>> juntar(int n, {String? mac, String prefixo = 's'}) async {
    await bib.adicionar([
      for (var i = 1; i <= n; i++)
        Importada(contaDeLinha('http://$prefixo$i.com/c/ ${mac ?? '00:1A:79:00:00:${i.toString().padLeft(2, '0')}'}')!),
    ]);
    return bib.listas.where((l) => l.conta.endereco.contains('//$prefixo')).toList();
  }

  ServicoVerificacao servico(Verificador f, {int workers = 4, DateTime Function()? agora, RitmoHost? ritmo}) =>
      ServicoVerificacao(bib,
          verificador: f, workers: workers, ritmo: ritmo ?? RitmoHost(intervalo: Duration.zero), agora: agora);

  Lista? daBib(Lista l) => bib.listas.where((x) => x.id == l.id).firstOrNull;

  test('com 3 a correr, verificarVarias de mais 2 junta-as à fila (total 5) e todas acabam', () async {
    final ls = await juntar(5);
    final f = _Falso();
    final s = servico(f, workers: 3);
    final primeiras = s.verificarVarias(ls.take(3));
    await _dar();
    expect(f.comecadas, hasLength(3));
    final outras = s.verificarVarias(ls.skip(3));
    expect((s.feitas, s.total), (0, 5));
    for (final l in ls) {
      f.soltar(l.conta.endereco);
    }
    await Future.wait([primeiras, outras]).timeout(const Duration(seconds: 5));
    expect(ls.every((l) => daBib(l)!.ultima?.estado == 'funciona'), isTrue);
    expect(s.ocupado, isFalse);
  });

  test('cancelar a 2.ª na fila: não é verificada, total 4 e as outras acabam', () async {
    final ls = await juntar(5);
    final f = _Falso();
    final s = servico(f, workers: 3);
    final todas = s.verificarVarias(ls);
    await _dar();
    expect(f.comecadas, hasLength(3));
    s.cancelar(ls[4].id);
    expect((s.feitas, s.total), (0, 4));
    expect(s.aVerificar(ls[4].id), isFalse);
    for (final l in ls) {
      f.soltar(l.conta.endereco);
    }
    await todas.timeout(const Duration(seconds: 5));
    expect(f.comecadas, isNot(contains(ls[4].conta.endereco)));
    expect(daBib(ls[4])!.ultima, isNull);
    expect(ls.take(4).every((l) => daBib(l)!.ultima?.estado == 'funciona'), isTrue);
  });

  test('feitas e total certos ao cancelar a meio', () async {
    final ls = await juntar(4);
    final f = _Falso();
    final s = servico(f, workers: 2);
    final todas = s.verificarVarias(ls);
    await _dar();
    f.soltar(ls[0].conta.endereco);
    await _dar();
    expect((s.feitas, s.total), (1, 4));
    s.cancelar(ls[1].id); // a correr
    expect((s.feitas, s.total), (1, 3));
    s.cancelar(ls[3].id); // na fila
    expect((s.feitas, s.total), (1, 2));
    f.soltar(ls[2].conta.endereco);
    await todas.timeout(const Duration(seconds: 5));
    expect(s.ocupado, isFalse);
    expect((s.feitas, s.total), (0, 0));
  });

  test('cancelar a que está a correr: o resultado dela não é gravado e as outras seguem', () async {
    final ls = await juntar(2);
    final f = _Falso(ignorarCancelamento: true);
    final s = servico(f, workers: 2);
    final todas = s.verificarVarias(ls);
    await _dar();
    s.cancelar(ls[0].id);
    expect(s.aVerificar(ls[0].id), isFalse);
    f.soltar(ls[0].conta.endereco); // o verificador devolve na mesma um resultado
    f.soltar(ls[1].conta.endereco);
    await todas.timeout(const Duration(seconds: 5));
    await _dar();
    expect(daBib(ls[0])!.ultima, isNull);
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
  });

  test('cancelar a que está a correr liberta logo o MAC, e só uma vez', () async {
    final ls = await juntar(3, mac: '00:1A:79:00:00:01');
    final f = _Falso(ignorarCancelamento: true); // a cancelada demora a sair
    final s = servico(f, workers: 4);
    final todas = s.verificarVarias(ls);
    await _dar();
    expect(f.comecadas, [ls[0].conta.endereco], reason: 'um MAC de cada vez');
    s.cancelar(ls[0].id);
    await _dar();
    expect(f.comecadas, [ls[0].conta.endereco, ls[1].conta.endereco], reason: 'o MAC foi libertado');
    f.soltar(ls[0].conta.endereco); // a cancelada acaba agora: não pode libertar o MAC outra vez
    await _dar();
    expect(f.comecadas, hasLength(2), reason: 'a 3.ª espera pela 2.ª (mesmo MAC)');
    f.soltar(ls[1].conta.endereco);
    f.soltar(ls[2].conta.endereco);
    await todas.timeout(const Duration(seconds: 5));
    expect(f.comecadas, hasLength(3));
  });

  test('cancelar a que espera a 2.ª volta: fica o resultado da 1.ª e não é retestada', () async {
    final ls = await juntar(2);
    var voltas2 = 0;
    final soltar = Completer<void>();
    final f = _Funcao((c, volta, can) async {
      if (volta == 2) {
        voltas2++;
        return const ResultadoVerificacao(EstadoV.funciona, 'abriu na 2.ª volta');
      }
      if (c.endereco == ls[0].conta.endereco) return const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado');
      await soltar.future;
      return const ResultadoVerificacao(EstadoV.funciona, 'ok');
    });
    final s = servico(f, workers: 2);
    final todas = s.verificarVarias(ls);
    // a 1.ª volta da 1.ª acaba (INC) e a da 2.ª fica presa: a 1.ª espera a 2.ª volta
    await _dar();
    expect(s.passos[ls[0].id], startsWith('inconclusiva: à espera'));
    s.cancelar(ls[0].id);
    expect((s.feitas, s.total), (0, 1));
    soltar.complete();
    await todas.timeout(const Duration(seconds: 5));
    expect(voltas2, 0);
    expect(daBib(ls[0])!.ultima?.estado, 'inconclusivo');
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
  });

  test('estimativaRestante: null antes da 1.ª; 2 feitas de 10 s e 3 por fazer dão 30 s', () async {
    final ls = await juntar(5);
    var agora = DateTime(2026, 11, 19, 10);
    final f = _Falso();
    final s = servico(f, workers: 5, agora: () => agora);
    expect(s.estimativaRestante, isNull);
    final todas = s.verificarVarias(ls);
    await _dar();
    expect(s.estimativaRestante, isNull);
    agora = agora.add(const Duration(seconds: 10));
    f.soltar(ls[0].conta.endereco);
    f.soltar(ls[1].conta.endereco);
    await _dar();
    expect((s.feitas, s.total), (2, 5));
    expect(s.estimativaRestante, const Duration(seconds: 30));
    // cancelar tira uma das por fazer
    s.cancelar(ls[4].id);
    expect(s.estimativaRestante, const Duration(seconds: 20));
    for (final l in ls) {
      f.soltar(l.conta.endereco);
    }
    await todas.timeout(const Duration(seconds: 5));
    expect(s.estimativaRestante, isNull, reason: 'acabou: começa do zero na próxima');
  });

  test('estimativaRestante não conta o tempo das 2.as voltas', () async {
    final ls = await juntar(2);
    var agora = DateTime(2026, 11, 19, 10);
    late ServicoVerificacao s;
    Duration? vista;
    final f = _Funcao((c, volta, can) async {
      if (volta == 1) {
        agora = agora.add(const Duration(seconds: 10));
        return const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado');
      }
      if (c.endereco == ls[0].conta.endereco) {
        agora = agora.add(const Duration(minutes: 5));
      } else {
        vista = s.estimativaRestante; // a 1.ª já foi retestada (5 min)
      }
      return const ResultadoVerificacao(EstadoV.funciona, 'abriu na 2.ª volta');
    });
    s = servico(f, workers: 1, agora: () => agora);
    await s.verificarVarias(ls).timeout(const Duration(seconds: 5));
    expect(vista, const Duration(seconds: 10), reason: 'média das 1.as voltas (10 s) × 1 por fazer');
  });

  test('dois serviços com o mesmo RitmoHost: cancelar num não liberta a vez que o outro tem', () async {
    final ls = await juntar(3, prefixo: 'p');
    final player = ls[0], x = ls[1], y = ls[2];
    // os três no mesmo servidor
    final ritmo = RitmoHost(intervalo: Duration.zero);
    final f = _NoServidor();
    final gestor = ServicoVerificacao(bib, verificador: f, ritmo: ritmo);
    final doPlayer = ServicoVerificacao(bib, verificador: f, ritmo: ritmo);
    final p = doPlayer.verificar(player);
    await _dar();
    expect(f.pedidos, [player.conta.endereco], reason: 'o Player tem a vez do servidor');
    final gx = gestor.verificar(x);
    final gy = gestor.verificar(y);
    await _dar();
    gestor.cancelar(x.id);
    await _dar();
    expect(f.pedidos, [player.conta.endereco], reason: 'Y espera que o Player acabe');
    expect(f.pico, 1);
    f.soltar.complete();
    await Future.wait([p, gx, gy]).timeout(const Duration(seconds: 5));
    expect(f.pedidos, [player.conta.endereco, y.conta.endereco]);
    expect(f.pico, 1);
    expect(daBib(x)!.ultima, isNull);
    expect(daBib(y)!.ultima?.estado, 'funciona');
  });
}

typedef _Comportamento = Future<ResultadoVerificacao> Function(Conta conta, int volta, Cancelamento? can);

/// Verificador falso ao nível de uma volta (a 2.ª tem o dobro do tempo).
class _Funcao extends Verificador {
  _Funcao(this.comportamento) : super(pausaReteste: Duration.zero);
  final _Comportamento comportamento;

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
          {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) =>
      comportamento(conta, timeout > const Duration(seconds: 8) ? 2 : 1, cancelamento);
}

/// Cada verificação faz um pedido ao mesmo servidor, na vez do [RitmoHost] da zona; o 1.º
/// pedido fica preso até `soltar`.
class _NoServidor extends Verificador {
  _NoServidor() : super(pausaReteste: Duration.zero);
  final soltar = Completer<void>();
  final pedidos = <String>[];
  int aCorrer = 0, pico = 0;

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    await comRitmo(Uri.parse('http://mesmo.com/'), cancelamento, () async {
      pedidos.add(conta.endereco);
      aCorrer++;
      if (aCorrer > pico) pico = aCorrer;
      try {
        if (pedidos.length == 1) await soltar.future;
        await _dar(10);
      } finally {
        aCorrer--;
      }
    });
    return const ResultadoVerificacao(EstadoV.funciona, 'ok');
  }
}
