import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/ui/player/continuar_direto.dart';

const _bloco = 64 * 1024;
const _reserva = 256 * 1024;
final _origem = Uri.parse('http://exemplo.invalid/live/u/p/1.ts');

/// O byte na posição absoluta `p` do stream falso: dá para conferir o que se lê.
List<int> _bytes(int desde, int n) => List<int>.generate(n, (i) => (desde + i) % 251);

/// O tamanho de tudo o que está na pasta agora (incluindo o bloco em escrita).
int _ocupado(Directory d) => d.existsSync()
    ? d.listSync().whereType<File>().fold<int>(0, (s, f) => s + f.lengthSync())
    : 0;

/// Bytes de um MPEG-TS falso a partir de `desde` dentro dele: cada pacote de 188 começa com 0x47 e
/// nenhum outro byte é 0x47.
List<int> _ts(int desde, int n) => List<int>.generate(n, (i) {
      final r = (desde + i) % 188;
      return r == 0 ? 0x47 : 1 + r % 50;
    });

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

  test('a regra do player: 3 reaberturas sem proveito passam, a 4.ª ligação falhada desiste, sem o URL',
      () async {
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
    expect(ligacoes, 4);
    expect(erros.map((e) => e.desistiu), [false, false, false, true]);
    for (final e in erros) {
      expect(e.mensagem, isNot(contains('exemplo.invalid')));
      expect(e.mensagem, isNot(contains('://')));
    }
    expect(esperas, ContinuarDireto.esperas);
    // desistiu: não volta a tentar
    await pumpEventQueue();
    expect(ligacoes, 4);
    await g.parar();
    expect(pasta.existsSync(), isFalse);
  });

  test('uma ligação com proveito recomeça a conta das falhas', () async {
    var ligacoes = 0;
    final ultima = StreamController<List<int>>();
    final sexta = Completer<void>();
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
      if (ligacoes == 6) {
        sexta.complete();
        return ultima.stream;
      }
      throw const SocketException('recusada');
    });
    final erros = <ErroGravador>[];
    g.erros.listen(erros.add);
    await g.iniciar();
    await sexta.future;
    await pumpEventQueue();
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

  test('parar() a meio de uma escrita também apaga tudo, e nada se escreve depois', () async {
    final (:g, :origem) = comOrigemManual();
    await g.iniciar();
    await enviar(g, origem, _bytes(0, 200000)); // 4 blocos no disco, o último em escrita
    expect(pasta.existsSync(), isTrue);
    origem.add(_bytes(200000, 200000)); // a escrita deste fica a meio
    await g.parar();
    expect(pasta.existsSync(), isFalse);
    origem.add(_bytes(400000, 1000)); // a origem ainda manda: já ninguém ouve
    await pumpEventQueue();
    expect(pasta.existsSync(), isFalse);
    expect(tmp.listSync(), isEmpty);
  });

  test('parar() durante iniciar() (ou antes) não deixa a pasta no disco', () async {
    final a = comOrigemManual();
    final aIniciar = a.g.iniciar(); // a pasta está a ser criada
    await a.g.parar();
    expect(pasta.existsSync(), isFalse);
    await aIniciar;
    await pumpEventQueue();
    expect(pasta.existsSync(), isFalse);

    final b = comOrigemManual();
    await b.g.parar();
    await b.g.iniciar(); // parado antes de começar: não cria nada
    await pumpEventQueue();
    expect(pasta.existsSync(), isFalse);
  });

  test('ler(desde, max) nunca devolve mais do que max, mesmo a atravessar blocos', () async {
    final (:g, :origem) = comOrigemManual();
    await g.iniciar();
    await enviar(g, origem, _bytes(0, 200000));
    expect(await g.ler(10, 70000), _bytes(10, 70000)); // atravessa a fronteira de 64 KiB
    expect((await g.ler(60000, 5000))!.length, 5000);
    expect(await g.ler(0, 0), isEmpty);
    expect(await g.ler(0, -5), isEmpty);
    expect(await g.ler(199990, 1000), _bytes(199990, 10)); // só o que há
    await g.parar();
  });

  test('alinhamento TS: uma ligação que começa a meio de um pacote alinha pelo primeiro 0x47', () async {
    var ligacoes = 0;
    final segunda = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: 1 << 20, tamanhoBloco: _bloco,
        agora: agora, esperar: nada, abrir: (_, _) async {
      ligacoes++;
      // a 1.ª começa a meio de um pacote (50 bytes dentro) e acaba a meio de outro
      if (ligacoes == 1) return Stream.fromIterable([_ts(50, 1000)]);
      return segunda.stream;
    });
    await g.iniciar();
    await g.crescimento.firstWhere((f) => f == 1000);
    relogio = relogio.add(const Duration(seconds: 1));
    // a 2.ª também começa a meio (outros 50 bytes), em pedaços de 1 s
    var q = 50;
    for (var k = 0; k < 6; k++) {
      await enviar(g, segunda, _ts(q, 20000));
      q += 20000;
      relogio = relogio.add(const Duration(seconds: 1));
    }
    expect(ligacoes, 2);
    // o primeiro pacote da 1.ª está em 188 − 50 = 138; o da 2.ª em 1000 + 138
    expect(g.posicaoHa(const Duration(hours: 1)), 138);
    // há 7 s a 1.ª ligação já tinha chegado toda: o direto era o começo da 2.ª, no primeiro pacote dela
    expect(g.posicaoHa(const Duration(seconds: 7)), 1000 + 138);
    final marcas = {for (var s = 1; s <= 7; s++) g.posicaoHa(Duration(seconds: s))};
    expect(marcas, contains(1000 + 138));
    expect(marcas.length, greaterThan(4));
    for (final p in marcas) {
      expect((await g.ler(p, 1))!.single, 0x47, reason: 'posição $p');
      expect(await g.ler(p + 188, 1), anyOf(isEmpty, [0x47]));
    }
    // alinhar: pela ligação que contém a posição, nunca para além do fim
    expect(g.alinhar(0), 138);
    expect(g.alinhar(138), 138);
    expect(g.alinhar(139), 138 + 188);
    expect(g.alinhar(138 + 4 * 188), 138 + 4 * 188);
    expect(g.alinhar(990), 1000 + 138); // o pacote cortado no fim da 1.ª: o primeiro da 2.ª
    expect(g.alinhar(1000), 1000 + 138);
    expect(g.alinhar(1000 + 139), 1000 + 138 + 188);
    expect(g.alinhar(g.fim + 500), g.fim);
    for (final p in [0, 777, 1001, 50000, 90000]) {
      final a = g.alinhar(p);
      expect(a, greaterThanOrEqualTo(p));
      if (a < g.fim) expect((await g.ler(a, 1))!.single, 0x47, reason: 'alinhar($p) = $a');
    }
    await g.parar();
  });

  test('obterOrigem: cada ligação (a primeira e as religações) pede a origem de novo', () async {
    var pedidas = 0;
    final vistos = <(Uri, Map<String, String>)>[];
    final segunda = StreamController<List<int>>();
    final g = GravadorDireto(
        origem: _origem,
        cabecalhos: const {},
        obterOrigem: () async {
          pedidas++;
          return (Uri.parse('http://exemplo.invalid/play/$pedidas.ts'), {'Cookie': 'link=$pedidas'});
        },
        pasta: pasta,
        reservaBytes: _reserva,
        tamanhoBloco: _bloco,
        agora: agora,
        esperar: nada,
        abrir: (u, c) async {
          vistos.add((u, c));
          // um link de uso único (Stalker): o mesmo link outra vez é recusado
          if (vistos.where((v) => v.$1 == u).length > 1) throw const HttpException('link gasto');
          if (vistos.length == 1) return Stream.fromIterable([_bytes(0, 1000)]);
          return segunda.stream;
        });
    await g.iniciar();
    await g.crescimento.firstWhere((f) => f == 1000);
    final alvo = g.crescimento.firstWhere((f) => f == 3000);
    // espera pela 2.ª ligação antes de enviar
    while (vistos.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    segunda.add(_bytes(1000, 2000));
    await alvo;
    expect(pedidas, 2);
    expect(vistos.map((v) => v.$1.path), ['/play/1.ts', '/play/2.ts']);
    expect(vistos.map((v) => v.$2['Cookie']), ['link=1', 'link=2']);
    expect(await g.ler(0, 3000), _bytes(0, 3000));
    await g.parar();
  });
}
