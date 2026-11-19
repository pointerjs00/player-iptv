import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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

/// Espera até a condição se cumprir, com prazo (a gravação em disco pode demorar com a máquina
/// carregada). Se o prazo acabar, volta na mesma e o `expect` a seguir diz o que falhou.
Future<void> _ate(bool Function() condicao, {Duration prazo = const Duration(seconds: 5)}) async {
  final fim = DateTime.now().add(prazo);
  while (!condicao() && DateTime.now().isBefore(fim)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}

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
    await _ate(() => f.comecadas.length == 3);
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
    await _ate(() => f.comecadas.length == 3);
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
    await _ate(() => f.comecadas.length == 2);
    f.soltar(ls[0].conta.endereco);
    await _ate(() => s.feitas == 1);
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
    await _ate(() => f.comecadas.length == 2);
    s.cancelar(ls[0].id);
    expect(s.aVerificar(ls[0].id), isFalse);
    f.soltar(ls[0].conta.endereco); // o verificador devolve na mesma um resultado
    f.soltar(ls[1].conta.endereco);
    await todas.timeout(const Duration(seconds: 5));
    await _ate(() => daBib(ls[1])!.ultima != null);
    expect(daBib(ls[0])!.ultima, isNull);
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
  });

  test('cancelar a que está a correr liberta logo o MAC, e só uma vez', () async {
    final ls = await juntar(3, mac: '00:1A:79:00:00:01');
    final f = _Falso(ignorarCancelamento: true); // a cancelada demora a sair
    final s = servico(f, workers: 4);
    final todas = s.verificarVarias(ls);
    await _ate(() => f.comecadas.isNotEmpty);
    expect(f.comecadas, [ls[0].conta.endereco], reason: 'um MAC de cada vez');
    s.cancelar(ls[0].id);
    await _ate(() => f.comecadas.length == 2);
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
    await _ate(() => s.passos[ls[0].id]?.startsWith('inconclusiva: à espera') ?? false);
    expect(s.passos[ls[0].id], startsWith('inconclusiva: à espera'));
    s.cancelar(ls[0].id);
    expect((s.feitas, s.total), (0, 1));
    soltar.complete();
    await todas.timeout(const Duration(seconds: 5));
    expect(voltas2, 0);
    expect(daBib(ls[0])!.ultima?.estado, 'inconclusivo');
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
  });

  test('estimativaRestante é o ritmo real da ronda: 2 de 4 feitas aos 10 s, a 2 de cada vez, faltam 10 s',
      () async {
    final ls = await juntar(4);
    var agora = DateTime(2026, 11, 19, 10);
    final f = _Falso();
    final s = servico(f, workers: 2, agora: () => agora);
    expect(s.estimativaRestante, isNull);
    final todas = s.verificarVarias(ls);
    await _ate(() => f.comecadas.length == 2);
    expect(f.comecadas, hasLength(2));
    expect(s.estimativaRestante, isNull, reason: 'nenhuma terminou');
    agora = agora.add(const Duration(seconds: 10));
    f.soltar(ls[0].conta.endereco);
    f.soltar(ls[1].conta.endereco);
    await _ate(() => s.feitas == 2 && f.comecadas.length == 4);
    expect((s.feitas, s.total), (2, 4));
    expect(f.comecadas, hasLength(4));
    // 10 s ÷ 2 terminadas × 2 por fazer
    expect(s.estimativaRestante, const Duration(seconds: 10));
    s.cancelar(ls[3].id); // cancelar tira uma das por fazer
    expect(s.estimativaRestante, const Duration(seconds: 5));
    f.soltar(ls[2].conta.endereco);
    await todas.timeout(const Duration(seconds: 5));
    expect(s.estimativaRestante, isNull, reason: 'acabou: começa do zero na próxima');
  });

  test('gravar não se cancela: cancelar durante a gravação da 1.ª volta é ignorado', () async {
    final ls = await juntar(1);
    final g = _Gravacao(bib);
    final s = ServicoVerificacao(bib,
        colecao: g,
        verificador: _Funcao((c, v, can) async => const ResultadoVerificacao(EstadoV.inconclusivo, 'sem canais')),
        ritmo: RitmoHost(intervalo: Duration.zero));
    g.prender = true;
    final fim = s.verificar(ls[0]);
    await _ate(() => g.aGravar == 1);
    expect(g.aGravar, 1);
    s.cancelar(ls[0].id);
    expect((s.aVerificar(ls[0].id), s.total), (true, 1), reason: 'já está a gravar');
    g.prender = false;
    g.soltar();
    await fim.timeout(const Duration(seconds: 5));
    expect(daBib(ls[0])!.ultima?.estado, 'inconclusivo');
  });

  test('gravar não se cancela: cancelar durante a gravação da 2.ª volta é ignorado', () async {
    final ls = await juntar(1);
    final g = _Gravacao(bib);
    final s = ServicoVerificacao(bib,
        colecao: g,
        verificador: _Funcao((c, volta, can) async => volta == 1
            ? const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado')
            : const ResultadoVerificacao(EstadoV.funciona, 'abriu na 2.ª volta')),
        ritmo: RitmoHost(intervalo: Duration.zero));
    g.prenderA = 2; // só a gravação da 2.ª volta fica presa
    final fim = s.verificar(ls[0]);
    await _ate(() => g.aGravar == 2);
    expect(g.aGravar, 2);
    s.cancelar(ls[0].id);
    expect((s.aVerificar(ls[0].id), s.total), (true, 1), reason: 'já está a gravar');
    g.soltar();
    await fim.timeout(const Duration(seconds: 5));
    expect(daBib(ls[0])!.ultima?.estado, 'funciona');
  });

  test('gravar que falha na 1.ª volta: a lista acaba, o serviço fica livre e as outras correm', () async {
    final ls = await juntar(2, mac: '00:1A:79:00:00:01'); // o mesmo MAC: a 2.ª só corre se o MAC sair
    final g = _Gravacao(bib)..falharId = ls[0].id;
    final s = ServicoVerificacao(bib,
        colecao: g,
        workers: 1,
        verificador: _Funcao((c, v, can) async => const ResultadoVerificacao(EstadoV.funciona, 'ok')),
        ritmo: RitmoHost(intervalo: Duration.zero));
    await s.verificarVarias(ls).timeout(const Duration(seconds: 5));
    expect(daBib(ls[0])!.ultima, isNull, reason: 'não se conseguiu gravar');
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
    expect((s.ocupado, s.feitas, s.total), (false, 0, 0));
    // e o serviço continua a servir
    await s.verificar(ls[0]).timeout(const Duration(seconds: 5));
    expect(s.ocupado, isFalse);
  });

  test('gravar que falha na 2.ª volta: a lista acaba, o serviço fica livre e as outras correm', () async {
    final ls = await juntar(2, mac: '00:1A:79:00:00:01');
    final g = _Gravacao(bib)
      ..falharId = ls[0].id
      ..falharSoNa = 2; // a 1.ª volta grava, a 2.ª falha
    final s = ServicoVerificacao(bib,
        colecao: g,
        workers: 1,
        verificador: _Funcao((c, volta, can) async => volta == 1 && c.endereco == ls[0].conta.endereco
            ? const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado')
            : const ResultadoVerificacao(EstadoV.funciona, 'ok')),
        ritmo: RitmoHost(intervalo: Duration.zero));
    await s.verificarVarias(ls).timeout(const Duration(seconds: 5));
    expect(daBib(ls[0])!.ultima?.estado, 'inconclusivo', reason: 'fica o da 1.ª volta');
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
    expect((s.ocupado, s.feitas, s.total), (false, 0, 0));
    await s.verificar(ls[1]).timeout(const Duration(seconds: 5));
    expect(s.ocupado, isFalse);
  });

  test('parar com uma a gravar: acaba quando a gravação sai e o serviço fica livre', () async {
    final ls = await juntar(2);
    final g = _Gravacao(bib)..prenderA = 1;
    final s = ServicoVerificacao(bib,
        colecao: g,
        workers: 1,
        verificador: _Funcao((c, v, can) async => const ResultadoVerificacao(EstadoV.funciona, 'ok')),
        ritmo: RitmoHost(intervalo: Duration.zero));
    final todas = s.verificarVarias(ls);
    await _ate(() => g.aGravar == 1);
    expect(g.aGravar, 1);
    s.parar();
    g.soltar();
    await todas.timeout(const Duration(seconds: 5));
    await _ate(() => !s.ocupado);
    expect(s.ocupado, isFalse);
    expect(daBib(ls[1])!.ultima, isNull, reason: 'a da fila saiu com o parar');
    await s.verificar(ls[1]).timeout(const Duration(seconds: 5));
    expect(daBib(ls[1])!.ultima?.estado, 'funciona');
  });

  test('estimativaRestante só conta as 1.as voltas como terminadas', () async {
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
    // 20 s das 1.as voltas + 5 min do reteste = 320 s, ÷ 2 terminadas (o reteste não conta) × 1
    expect(vista, const Duration(seconds: 160));
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
    await _ate(() => f.pedidos.isNotEmpty);
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

/// Coleção que grava na biblioteca, mas pode prender a gravação até `soltar`.
class _Gravacao implements ColecaoListas {
  _Gravacao(this.bib);
  final Biblioteca bib;
  bool prender = false;
  int? prenderA; // prende só a n.ª gravação
  int aGravar = 0;
  final _porta = Completer<void>();

  /// As gravações desta lista falham; com `falharSoNa`, só a n.ª dela.
  String? falharId;
  int? falharSoNa;
  int _dela = 0;

  void soltar() {
    if (!_porta.isCompleted) _porta.complete();
  }

  @override
  Future<void> registarVerificacao(String id, UltimaVerificacao v) async {
    aGravar++;
    if (prender || prenderA == aGravar) await _porta.future;
    if (id == falharId && (falharSoNa == null || ++_dela == falharSoNa)) {
      throw const FileSystemException('disco cheio');
    }
    await bib.registarVerificacao(id, v);
  }

  @override
  List<Lista> get listas => bib.listas;
  @override
  Lista? porId(String id) => bib.porId(id);
  @override
  void addListener(VoidCallback l) => bib.addListener(l);
  @override
  void removeListener(VoidCallback l) => bib.removeListener(l);
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
