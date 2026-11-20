import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/gravador.dart';

const _bloco = 64 * 1024;
const _reserva = 256 * 1024;
final _origem = Uri.parse('http://exemplo.invalid/live/u/p/1.ts');

/// O byte na posição absoluta `p` do stream falso: dá para conferir o que se lê.
List<int> _bytes(int desde, int n) => List<int>.generate(n, (i) => (desde + i) % 251);

/// O tamanho de tudo o que está na pasta agora (incluindo o bloco em escrita).
int _ocupado(Directory d) => d.existsSync()
    ? d.listSync().whereType<File>().fold<int>(0, (s, f) => s + f.lengthSync())
    : 0;

int _alinharAcima(int p) => (p + 187) ~/ 188 * 188;

void main() {
  late Directory tmp;
  late Directory pasta;
  var relogio = DateTime(2026, 11, 20, 20);
  DateTime agora() => relogio;
  Future<void> nada(Duration _) async {}

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gravador_test');
    pasta = Directory('${tmp.path}${Platform.pathSeparator}sessao');
    relogio = DateTime(2026, 11, 20, 20);
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Um gravador cuja origem é um StreamController que o teste alimenta (nunca fecha sozinho).
  ({GravadorDireto g, StreamController<List<int>> origem}) comOrigemManual({int reserva = _reserva}) {
    final c = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {'Cookie': 'mac=x'}, pasta: pasta, reservaBytes: reserva,
        tamanhoBloco: _bloco, agora: agora, esperar: nada, abrir: (_, _) async => c.stream);
    return (g: g, origem: c);
  }

  Future<void> enviar(GravadorDireto g, StreamController<List<int>> c, List<int> dados) async {
    final alvo = g.fim + dados.length;
    final chegou = g.crescimento.firstWhere((f) => f >= alvo);
    c.add(dados);
    await chegou;
  }

  test('o espaço na pasta nunca passa da reserva, contando o bloco em escrita; o início avança', () async {
    final (:g, :origem) = comOrigemManual();
    await g.iniciar();
    var maximo = 0;
    var inicioAntes = g.inicio;
    var avancou = 0;
    // um vigia a cada crescimento, além da conta antes e depois de cada pedaço
    final vigia = g.crescimento.listen((_) {
      final o = _ocupado(pasta);
      if (o > maximo) maximo = o;
      expect(o, lessThanOrEqualTo(_reserva));
    });
    const total = 3200 * 1024; // 3,2 MiB
    const pedaco = 50000; // não divide o bloco: há pedaços que atravessam dois blocos
    while (g.fim < total) {
      expect(_ocupado(pasta), lessThanOrEqualTo(_reserva));
      final n = total - g.fim < pedaco ? total - g.fim : pedaco;
      await enviar(g, origem, _bytes(g.fim, n));
      final o = _ocupado(pasta);
      if (o > maximo) maximo = o;
      expect(o, lessThanOrEqualTo(_reserva));
      expect(pasta.listSync().length, lessThanOrEqualTo(_reserva ~/ _bloco));
      expect(g.inicio, greaterThanOrEqualTo(inicioAntes));
      if (g.inicio > inicioAntes) avancou++;
      inicioAntes = g.inicio;
    }
    await vigia.cancel();
    expect(g.fim, total);
    expect(avancou, greaterThan(40)); // ~50 blocos rodaram
    expect(maximo, greaterThan(3 * _bloco)); // usa a reserva toda, não menos
    expect(g.fim - g.inicio, lessThanOrEqualTo(_reserva));
    expect(g.fim - g.inicio, greaterThan(3 * _bloco));
    // o que lá está é o que veio, e o que foi apagado já não se lê
    expect(await g.ler(g.inicio, 1000), _bytes(g.inicio, 1000));
    final meio = g.fim - 100000;
    expect(await g.ler(meio, 100000), _bytes(meio, 100000));
    expect(await g.ler(0, 10), isNull);
    expect(await g.ler(g.inicio - 1, 10), isNull);
    expect(await g.ler(g.fim, 10), isEmpty);
    await g.parar();
  });

  test('a reserva menor do que um bloco é recusada (não haveria como cumprir o limite)', () {
    expect(
        () => GravadorDireto(origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: _bloco - 1,
            tamanhoBloco: _bloco),
        throwsArgumentError);
  });

  test('índice de tempo: posicaoHa, recuoDe e janela com o relógio falso', () async {
    final (:g, :origem) = comOrigemManual(reserva: 1 << 20);
    await g.iniciar();
    expect(g.janela, Duration.zero);
    const n = 10;
    for (var k = 0; k < n; k++) {
      await enviar(g, origem, _bytes(g.fim, _bloco)); // 64 KiB por segundo
      relogio = relogio.add(const Duration(seconds: 1));
    }
    expect(g.fim, n * _bloco);
    final ha2 = g.posicaoHa(const Duration(seconds: 2));
    expect(ha2, _alinharAcima(g.fim - 128 * 1024));
    expect(ha2 % 188, 0);
    final r = g.recuoDe(ha2);
    expect(r, lessThanOrEqualTo(const Duration(seconds: 2)));
    expect(r, greaterThan(const Duration(milliseconds: 1900)));
    expect(g.recuoDe(g.fim), Duration.zero);
    expect(g.janela, const Duration(seconds: n));
    // mais do que há: limitado ao início
    expect(g.posicaoHa(const Duration(hours: 1)), _alinharAcima(g.inicio));
    await g.parar();
  });

  test('o índice fica limitado ao início depois de os blocos rodarem', () async {
    final (:g, :origem) = comOrigemManual();
    await g.iniciar();
    for (var k = 0; k < 10; k++) {
      await enviar(g, origem, _bytes(g.fim, _bloco));
      relogio = relogio.add(const Duration(seconds: 1));
    }
    expect(g.inicio, greaterThan(0));
    final p = g.posicaoHa(const Duration(hours: 1));
    expect(p, _alinharAcima(g.inicio));
    expect(await g.ler(p, 188), _bytes(p, 188));
    expect(g.janela, lessThanOrEqualTo(const Duration(seconds: 4)));
    expect(g.janela, greaterThanOrEqualTo(const Duration(seconds: 3)));
    await g.parar();
  });

  test('a origem fecha a meio: volta a ligar e continua com o fim contínuo no mesmo bloco', () async {
    var ligacoes = 0;
    final segunda = StreamController<List<int>>();
    final erros = <ErroGravador>[];
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {'Cookie': 'mac=x'}, pasta: pasta, reservaBytes: _reserva,
        tamanhoBloco: _bloco, agora: agora, esperar: nada, abrir: (u, c) async {
      expect(u, _origem);
      expect(c['Cookie'], 'mac=x');
      ligacoes++;
      if (ligacoes == 1) {
        relogio = relogio.add(const Duration(seconds: 6));
        return Stream.fromIterable([_bytes(0, 30000), _bytes(30000, 10000)]);
      }
      return segunda.stream;
    });
    g.erros.listen(erros.add);
    await g.iniciar();
    await g.crescimento.firstWhere((f) => f == 40000);
    await enviar(g, segunda, _bytes(40000, 50000));
    expect(ligacoes, 2);
    expect(g.fim, 90000);
    expect(await g.ler(0, 90000), _bytes(0, 90000));
    expect(pasta.listSync().length, 2); // 90000 bytes = um bloco cheio e outro a meio
    expect(erros.where((e) => e.desistiu), isEmpty);
    await g.parar();
  });

  test('3 falhas seguidas sem proveito: desiste, sem o URL na mensagem', () async {
    var ligacoes = 0;
    final esperas = <Duration>[];
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: _reserva, tamanhoBloco: _bloco,
        agora: agora, esperar: (d) async => esperas.add(d), abrir: (_, _) async {
      ligacoes++;
      if (ligacoes == 2) return Stream.fromIterable([_bytes(0, 1000)]); // fecha logo: sem proveito
      throw SocketException('falhou a ligação a $_origem');
    });
    final erros = <ErroGravador>[];
    final desistiu = Completer<void>();
    g.erros.listen((e) {
      erros.add(e);
      if (e.desistiu) desistiu.complete();
    });
    await g.iniciar();
    await desistiu.future;
    expect(ligacoes, 3);
    expect(erros.length, 3);
    expect(erros.map((e) => e.desistiu), [false, false, true]);
    for (final e in erros) {
      expect(e.mensagem, isNot(contains('exemplo.invalid')));
      expect(e.mensagem, isNot(contains('://')));
    }
    expect(esperas, hasLength(2));
    // desistiu: não volta a tentar
    await Future<void>.delayed(Duration.zero);
    expect(ligacoes, 3);
    await g.parar();
    expect(pasta.existsSync(), isFalse);
  });

  test('uma ligação com proveito recomeça a conta das falhas', () async {
    var ligacoes = 0;
    final ultima = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: _reserva, tamanhoBloco: _bloco,
        agora: agora, esperar: nada, abrir: (_, _) async {
      ligacoes++;
      if (ligacoes == 3) {
        // 6 s de dados: tem proveito
        return Stream.fromIterable([0, 1]).asyncMap((i) {
          if (i == 1) relogio = relogio.add(const Duration(seconds: 6));
          return _bytes(i * 100, 100);
        });
      }
      if (ligacoes == 6) return ultima.stream;
      throw const SocketException('recusada');
    });
    final erros = <ErroGravador>[];
    g.erros.listen(erros.add);
    await g.iniciar();
    while (ligacoes < 6) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(erros.map((e) => e.desistiu), everyElement(isFalse));
    expect(erros, hasLength(5));
    await g.parar();
  });

  test('parar() apaga a pasta e os blocos; parar(apagar: false) deixa-os', () async {
    final (:g, :origem) = comOrigemManual();
    await g.iniciar();
    await enviar(g, origem, _bytes(0, 100000));
    expect(pasta.existsSync(), isTrue);
    expect(_ocupado(pasta), 100000);
    await g.parar();
    expect(pasta.existsSync(), isFalse);
    expect(tmp.listSync(), isEmpty);
    expect(await g.ler(0, 10), isNull);

    final outro = comOrigemManual();
    await outro.g.iniciar();
    await enviar(outro.g, outro.origem, _bytes(0, 1000));
    await outro.g.parar(apagar: false);
    expect(_ocupado(pasta), 1000);
  });

  test('parar() a meio de uma escrita ou com a origem parada também apaga tudo', () async {
    final c = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: _reserva, tamanhoBloco: _bloco,
        agora: agora, esperar: nada, abrir: (_, _) async => c.stream);
    await g.iniciar();
    c.add(_bytes(0, 200000));
    c.add(_bytes(200000, 200000));
    await g.parar();
    expect(pasta.existsSync(), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(pasta.existsSync(), isFalse); // nada a escrever depois de parar
  });
}
