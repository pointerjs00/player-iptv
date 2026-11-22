import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

typedef _Comportamento = Future<ResultadoVerificacao> Function(Conta conta, int volta, Cancelamento? can);

/// Verificador falso ao nível de uma volta: regista quem corre, quando e em que volta.
class _Falso extends Verificador {
  _Falso(this.comportamento, {super.limiteConta}) : super(pausaReteste: Duration.zero);
  final _Comportamento comportamento;
  final eventos = <(String, String, int)>[]; // (início|fim, endereço, volta)
  final aCorrer = <Conta>[];
  int picoMesmoMac = 0, picoVolta2 = 0;

  /// O serviço dá o limite por lista das Definições; aqui vale o `limiteConta` do teste.
  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
          {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso, Duration? limite}) =>
      super.verificarComLimite(conta, canaisTeste, timeout: timeout, cancelamento: cancelamento, aviso: aviso);

  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, Aviso? aviso}) async {
    final volta = timeout > const Duration(seconds: 8) ? 2 : 1;
    aCorrer.add(conta);
    final macs = aCorrer.where((c) => c.mac.isNotEmpty && c.mac == conta.mac).length;
    picoMesmoMac = max(picoMesmoMac, macs);
    eventos.add(('início', conta.endereco, volta));
    picoVolta2 = max(picoVolta2, eventos.where((e) => e.$3 == 2 && e.$1 == 'início').length -
        eventos.where((e) => e.$3 == 2 && e.$1 == 'fim').length);
    try {
      return await comportamento(conta, volta, cancelamento);
    } finally {
      aCorrer.remove(conta);
      eventos.add(('fim', conta.endereco, volta));
    }
  }
}

Future<void> _esperar(int ms, Cancelamento? can) async {
  for (var i = 0; i < ms ~/ 10; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    can?.verificar();
  }
}

void main() {
  group('I3: ritmo por servidor', () {
    late HttpServer srv;
    var aCorrer = 0, pico = 0, pedidos429 = 0;
    final inicios = <DateTime>[];
    setUp(() async {
      aCorrer = pico = pedidos429 = 0;
      inicios.clear();
      srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      srv.listen((p) async {
        aCorrer++;
        pico = max(pico, aCorrer);
        inicios.add(DateTime.now());
        final limitado = p.uri.path == '/429' && pedidos429++ == 0;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        aCorrer--;
        p.response.statusCode = limitado ? 429 : 200;
        if (limitado) p.response.headers.set('Retry-After', '0');
        p.response.write('ok');
        await p.response.close();
      });
    });
    tearDown(() => srv.close(force: true));

    test('I3: um pedido de cada vez por servidor, com intervalo entre pedidos', () async {
      final ritmo = RitmoHost(intervalo: const Duration(milliseconds: 150));
      final url = 'http://127.0.0.1:${srv.port}/x';
      await runZoned(() => Future.wait([for (var i = 0; i < 4; i++) obterTexto(url)]),
          zoneValues: {ritmoZona: ritmo});
      expect(pico, 1);
      for (var i = 1; i < inicios.length; i++) {
        expect(inicios[i].difference(inicios[i - 1]).inMilliseconds, greaterThanOrEqualTo(180));
      }
    });

    test('I3: 429 com Retry-After é repetido', () async {
      final r = await runZoned(() => obterTexto('http://127.0.0.1:${srv.port}/429'),
          zoneValues: {ritmoZona: RitmoHost(intervalo: Duration.zero)});
      expect((r, pedidos429), ('ok', 2));
    });
  });

  group('I3: serviço', () {
    late Directory pasta;
    late Biblioteca bib;
    setUp(() async {
      pasta = Directory.systemTemp.createTempSync('ritmo');
      bib = await Biblioteca.abrir(pasta);
    });
    tearDown(() {
      try {
        pasta.deleteSync(recursive: true);
      } on FileSystemException {/* Windows */}
    });

    Future<void> juntar(List<String> linhas) =>
        bib.adicionar([for (final l in linhas) Importada(contaDeLinha(l)!)]);

    test('I3: duas listas com o mesmo MAC nunca são testadas ao mesmo tempo', () async {
      await juntar([
        'http://a.com/c/ 00:1A:79:00:00:01',
        'http://a.com/stalker_portal/c/ 00:1A:79:00:00:01',
        'http://b.com/c/ 00:1A:79:00:00:01',
        'http://c.com/c/ 00:1A:79:00:00:02',
      ]);
      final f = _Falso((c, v, can) async {
        await _esperar(60, can);
        return const ResultadoVerificacao(EstadoV.funciona, 'ok');
      });
      final s = ServicoVerificacao(bib, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      expect(f.picoMesmoMac, 1);
      expect(bib.listas.every((l) => l.ultima?.estado == 'funciona'), isTrue);
    });

    test('a 2.ª volta começa logo que o servidor da lista está livre, sem esperar pelas outras', () async {
      await juntar(['http://rapida.com/c/ 00:1A:79:00:00:01', 'http://lenta.com/c/ 00:1A:79:00:00:02',
          'http://boa.com/c/ 00:1A:79:00:00:03']);
      final f = _Falso((c, volta, can) async {
        await _esperar(c.endereco.contains('rapida') ? 10 : 200, can);
        if (c.endereco.contains('boa')) return const ResultadoVerificacao(EstadoV.funciona, 'ok');
        return volta == 1
            ? const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado')
            : const ResultadoVerificacao(EstadoV.funciona, 'abriu na 2.ª volta');
      });
      final s = ServicoVerificacao(bib, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      final ultimoFimVolta1 = f.eventos.lastIndexWhere((e) => e.$1 == 'fim' && e.$3 == 1);
      final reteste = f.eventos.indexWhere((e) => e.$1 == 'início' && e.$3 == 2 && e.$2.contains('rapida'));
      expect(reteste, lessThan(ultimoFimVolta1), reason: 'a rápida não espera pelas lentas: ${f.eventos}');
      expect(f.eventos.where((e) => e.$1 == 'início' && e.$3 == 2), hasLength(2));
      expect(bib.listas.map((l) => l.ultima!.estado), ['funciona', 'funciona', 'funciona']);
      expect(s.ocupado, isFalse);
    });

    test('a 2.ª volta nunca junta carga a um servidor que está a ser testado', () async {
      // duas listas no mesmo servidor (MACs diferentes): a 1.ª fica INC depressa, a 2.ª demora
      await juntar(['http://mesmo.com/c/ 00:1A:79:00:00:01', 'http://mesmo.com/stalker_portal/c/ 00:1A:79:00:00:02']);
      final f = _Falso((c, volta, can) async {
        if (volta == 1 && c.endereco.contains('stalker_portal')) {
          await _esperar(200, can);
          return const ResultadoVerificacao(EstadoV.funciona, 'ok');
        }
        return volta == 1
            ? const ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado')
            : const ResultadoVerificacao(EstadoV.funciona, 'abriu na 2.ª volta');
      });
      final s = ServicoVerificacao(bib, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      final fimLenta = f.eventos.indexWhere((e) => e.$1 == 'fim' && e.$2.contains('stalker_portal'));
      final reteste = f.eventos.indexWhere((e) => e.$1 == 'início' && e.$3 == 2);
      expect(reteste, greaterThan(fimLenta), reason: '${f.eventos}');
      expect(bib.listas.map((l) => l.ultima!.estado), ['funciona', 'funciona']);
    });

    test('inconclusiva com um motivo que não muda ("conta sem canais") não tem 2.ª volta', () async {
      await juntar(['http://vazia.com/c/ 00:1A:79:00:00:01']);
      final f = _Falso((c, volta, can) async =>
          const ResultadoVerificacao(EstadoV.inconclusivo, 'conta sem canais', repeticao: Repeticao.inutil));
      final s = ServicoVerificacao(bib, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      expect(f.eventos.where((e) => e.$1 == 'início'), hasLength(1));
      expect(bib.listas.single.ultima!.motivo, 'conta sem canais');
    });

    test('as que já eram inconclusivas vão à frente e começam com o dobro do tempo', () async {
      await juntar(['http://a.com/c/ 00:1A:79:00:00:01', 'http://b.com/c/ 00:1A:79:00:00:02',
          'http://c.com/c/ 00:1A:79:00:00:03']);
      final c = bib.listas.firstWhere((l) => l.conta.endereco.contains('c.com'));
      await bib.registarVerificacao(c.id,
          UltimaVerificacao(estado: 'inconclusivo', motivo: 'tempo esgotado', data: DateTime(2026, 11, 1)));
      final f = _Falso((c, volta, can) async => const ResultadoVerificacao(EstadoV.funciona, 'ok'));
      final s = ServicoVerificacao(bib, verificador: f, workers: 1, ritmo: RitmoHost(intervalo: Duration.zero));
      await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      final inicios = f.eventos.where((e) => e.$1 == 'início').toList();
      expect(inicios.first.$2, contains('c.com'));
      expect(inicios.first.$3, 2, reason: 'o _Falso vê o dobro do tempo como 2.ª volta');
      expect(inicios.skip(1).map((e) => e.$3), [1, 1]);
    });

    test('I3: uma conta que não acaba fica INC com "tempo esgotado (limite …)"', () async {
      await juntar(['http://lenta.com/c/ 00:1A:79:00:00:01']);
      var parou = false;
      final f = _Falso((c, v, can) async {
        try {
          await _esperar(100000, can);
        } on Cancelado {
          parou = true;
          rethrow;
        }
        return const ResultadoVerificacao(EstadoV.funciona, 'ok');
      }, limiteConta: const Duration(milliseconds: 200));
      final s = ServicoVerificacao(bib, verificador: f, ritmo: RitmoHost(intervalo: Duration.zero));
      try {
        await s.verificarVarias(bib.listas).timeout(const Duration(seconds: 5));
      } finally {
        s.parar();
      }
      final u = bib.listas.single.ultima!;
      expect(u.estado, 'inconclusivo');
      expect(u.motivo, startsWith('tempo esgotado (limite de'));
      expect(parou, isTrue, reason: 'os pedidos da conta são cancelados');
    });
  });
}
