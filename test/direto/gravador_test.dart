import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/armazem.dart';
import 'package:player_iptv/direto/costura.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/ui/player/continuar_direto.dart';

import 'ts_sintetico.dart';

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

/// Os blocos na pasta (sem o ficheiro de bloqueio da sessão).
List<File> _blocosNoDisco(Directory d) =>
    d.listSync().whereType<File>().where((f) => f.uri.pathSegments.last.startsWith('bloco_')).toList();

/// Um armazém em memória cuja escrita falha quando o teste quiser (a pasta apagada pelo sistema,
/// um erro do armazenamento que não é falta de espaço).
class _ArmazemQueFalha implements ArmazemBlocos {
  _ArmazemQueFalha(int bloco) : _m = ArmazemMemoria(bloco);
  final ArmazemMemoria _m;
  bool falhar = false;

  @override
  Future<void> preparar() => _m.preparar();
  @override
  Future<void> abrir(int n) => _m.abrir(n);
  @override
  Future<void> escrever(List<int> dados, int de, int ate) {
    if (falhar) throw const FileSystemException('a pasta desapareceu', '/cache/direto/s1/bloco_0.ts');
    return _m.escrever(dados, de, ate);
  }

  @override
  Future<void> fecharAberto() => _m.fecharAberto();
  @override
  Future<int> apagar(int n) => _m.apagar(n);
  @override
  Future<List<int>> ler(int n, int posicao, int quanto) => _m.ler(n, posicao, quanto);
  @override
  Future<void> fechar({required bool apagar}) => _m.fechar(apagar: apagar);
}

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
      expect(_blocosNoDisco(pasta).length, lessThanOrEqualTo(_reserva ~/ _bloco));
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
    expect(_blocosNoDisco(pasta).length, 2); // 90000 bytes = um bloco cheio e outro a meio
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

  test('o bloqueio da sessão falhou: o ficheiro não fica aberto e a pasta apaga-se toda', () async {
    // outro handle já tem o ficheiro de bloqueio bloqueado: o lock desta sessão falha
    pasta.createSync(recursive: true);
    final outro = File('${pasta.path}${Platform.pathSeparator}${ArmazemDisco.nomeBloqueio}').openSync(mode: FileMode.append);
    outro.lockSync(FileLock.exclusive);
    final armazem = ArmazemDisco(pasta);
    await armazem.preparar();
    outro.unlockSync();
    outro.closeSync();
    await armazem.fechar(apagar: true);
    expect(pasta.existsSync(), isFalse, reason: 'no Windows um handle aberto impedia de apagar a pasta');
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

  group('espaço livre do aparelho durante a gravação', () {
    const gb = 1 << 30;

    /// Um gravador de 16 blocos (1 MiB) com o espaço livre falso: `livreSemPasta` menos o que a
    /// pasta ocupa agora (cada bloco apagado devolve o seu espaço).
    ({GravadorDireto g, StreamController<List<int>> origem, List<int> medicoes}) comEspaco(
        int Function() livreSemPasta) {
      final c = StreamController<List<int>>();
      final medicoes = <int>[];
      final g = GravadorDireto(
          origem: _origem,
          cabecalhos: const {},
          pasta: pasta,
          reservaBytes: 16 * _bloco,
          tamanhoBloco: _bloco,
          agora: agora,
          esperar: nada,
          abrir: (_, _) async => c.stream,
          espacoLivre: () async {
            final l = livreSemPasta() - _ocupado(pasta);
            medicoes.add(l);
            return l;
          });
      return (g: g, origem: c, medicoes: medicoes);
    }

    test('sem 1 GB + um bloco livres, apagam-se os mais antigos (medindo depois de cada um) antes do novo',
        () async {
      var livre = gb + 100 * _bloco;
      final (:g, :origem, :medicoes) = comEspaco(() => livre);
      await g.iniciar();
      await enviar(g, origem, _bytes(0, 8 * _bloco)); // 8 blocos (o 8.º ainda aberto, cheio)
      expect(medicoes, hasLength(8), reason: 'mede-se a cada bloco novo');
      expect(g.inicio, 0, reason: 'com espaço não se apaga nada');
      // outra app ocupou espaço: agora há 1 GB − 3,5 blocos livres
      livre = gb + 8 * _bloco - (3 * _bloco + _bloco ~/ 2);
      await enviar(g, origem, _bytes(g.fim, 100));
      // o 8.º fechou (8 no disco): para ter 1 GB + 1 bloco apagam-se os 5 mais antigos, um a um
      expect(g.inicio, 5 * _bloco);
      expect(_blocosNoDisco(pasta), hasLength(4), reason: '3 antigos + o novo');
      expect(medicoes, hasLength(8 + 1 + 5), reason: 'mede-se outra vez depois de cada bloco apagado');
      expect(livre - _ocupado(pasta) - (_bloco - 100), greaterThanOrEqualTo(gb),
          reason: 'a margem de 1 GB fica mesmo com o bloco novo cheio');
      expect(await g.ler(5 * _bloco, 10), _bytes(5 * _bloco, 10));
      expect(await g.ler(0, 10), isNull, reason: 'apagado');
      // continua a gravar
      await enviar(g, origem, _bytes(g.fim, 2 * _bloco));
      expect(g.fim, 10 * _bloco + 100);
      await g.parar();
    });

    test('se nem a apagar até restar 1 bloco chega a 1 GB: pára de gravar, larga a origem e avisa', () async {
      var livre = gb + 100 * _bloco;
      final (:g, :origem, medicoes: _) = comEspaco(() => livre);
      final erros = <ErroGravador>[];
      g.erros.listen(erros.add);
      var cancelada = false;
      origem.onCancel = () => cancelada = true;
      await g.iniciar();
      await enviar(g, origem, _bytes(0, 6 * _bloco));
      livre = gb; // com os 6 blocos na pasta, ficam 6 abaixo da margem; apagar 5 não chega
      origem.add(_bytes(g.fim, 100));
      await g.erros.first;
      await pumpEventQueue();
      expect(erros, hasLength(1));
      expect(erros.single.semEspaco, isTrue);
      expect(erros.single.desistiu, isTrue, reason: 'o gravador não volta a ligar');
      expect(erros.single.mensagem, isNot(contains('exemplo.invalid')));
      expect(cancelada, isTrue, reason: 'a ligação à origem fecha: o canal pode reabrir na origem');
      expect(g.fim, 6 * _bloco, reason: 'nada mais se grava');
      expect(_blocosNoDisco(pasta), hasLength(1), reason: 'apagou até restar 1 bloco');
      await g.parar();
      expect(pasta.existsSync(), isFalse);
    });

    test('um erro de escrita que não é falta de espaço também passa ao anel em RAM (semEspaco)', () async {
      final c = StreamController<List<int>>();
      final armazem = _ArmazemQueFalha(_bloco);
      final g = GravadorDireto(
          origem: _origem, cabecalhos: const {}, armazem: armazem, reservaBytes: _reserva, tamanhoBloco: _bloco,
          agora: agora, esperar: nada, abrir: (_, _) async => c.stream);
      final erros = <ErroGravador>[];
      g.erros.listen(erros.add);
      await g.iniciar();
      await enviar(g, c, _bytes(0, 1000));
      armazem.falhar = true;
      c.add(_bytes(1000, 100));
      await g.erros.first;
      await pumpEventQueue();
      expect(erros, hasLength(1));
      expect(erros.single.desistiu, isTrue, reason: 'não adianta voltar a ligar');
      expect(erros.single.semEspaco, isTrue, reason: 'a origem está boa: o player passa ao anel em RAM');
      expect(erros.single.mensagem, isNot(contains('/cache')));
      await g.parar();
    });

    test('em memória: a soma dos blocos nunca passa da reserva e nada vai para o disco', () async {
      final c = StreamController<List<int>>();
      final armazem = ArmazemMemoria(_bloco);
      final g = GravadorDireto(
          origem: _origem, cabecalhos: const {}, armazem: armazem, reservaBytes: _reserva, tamanhoBloco: _bloco,
          agora: agora, esperar: nada, abrir: (_, _) async => c.stream);
      await g.iniciar();
      var maximo = 0;
      final vigia = g.crescimento.listen((_) {
        expect(armazem.bytesEmUso, lessThanOrEqualTo(_reserva));
        if (armazem.bytesEmUso > maximo) maximo = armazem.bytesEmUso;
      });
      const total = 3200 * 1024; // 12,5 vezes a reserva
      while (g.fim < total) {
        expect(armazem.bytesEmUso, lessThanOrEqualTo(_reserva));
        final n = total - g.fim < 50000 ? total - g.fim : 50000;
        await enviar(g, c, _bytes(g.fim, n));
      }
      expect(maximo, _reserva - _bloco,
          reason: 'a reserva enche-se toda, menos a folga da procura da costura (um bloco)');
      expect(g.folgaProcura, _bloco);
      expect(g.inicio, greaterThanOrEqualTo(total - _reserva));
      expect(await g.ler(g.inicio, 70000), _bytes(g.inicio, 70000), reason: 'atravessa blocos em memória');
      expect(await g.ler(g.fim - 1000, 5000), _bytes(g.fim - 1000, 1000));
      expect(await g.ler(0, 10), isNull, reason: 'já saiu da memória');
      expect(pasta.existsSync(), isFalse, reason: 'nada no disco');
      await vigia.cancel();
      await g.parar();
      expect(armazem.bytesEmUso, 0, reason: 'parar larga a memória');
      expect(await g.ler(g.fim - 10, 10), isNull);
    });

    test('sem saber o espaço (null) não se apaga nada além da reserva', () async {
      final c = StreamController<List<int>>();
      var medidas = 0;
      final g = GravadorDireto(
          origem: _origem, cabecalhos: const {}, pasta: pasta, reservaBytes: 4 * _bloco, tamanhoBloco: _bloco,
          agora: agora, esperar: nada, abrir: (_, _) async => c.stream,
          espacoLivre: () async {
            medidas++;
            return null;
          });
      await g.iniciar();
      await enviar(g, c, _bytes(0, 6 * _bloco + 1));
      expect(medidas, 7);
      expect(g.inicio, 3 * _bloco, reason: 'só a rotação da reserva (4 blocos)');
      await g.parar();
    });
  });

  group('costura das religações (TS sintético)', () {
    /// Um gravador em memória cujas ligações são `ligacoes` (cada uma, os pedaços que manda; cada
    /// pedaço avança 1 s no relógio); depois delas, uma ligação que nunca fecha (`ultima`).
    ({GravadorDireto g, ArmazemMemoria armazem, StreamController<List<int>> ultima, Future<void> todas})
        comLigacoes(List<List<List<int>>> ligacoes, {int limite = limiteProcura}) {
      final ultima = StreamController<List<int>>();
      final todas = Completer<void>();
      final armazem = ArmazemMemoria(_bloco);
      var n = 0;
      final g = GravadorDireto(
          origem: _origem,
          cabecalhos: const {},
          armazem: armazem,
          reservaBytes: 64 * _bloco, // 4 MiB
          tamanhoBloco: _bloco,
          agora: agora,
          esperar: nada,
          limiteCostura: limite,
          abrir: (_, _) async {
            if (n < ligacoes.length) {
              return Stream.fromIterable(ligacoes[n++]).map((p) {
                relogio = relogio.add(const Duration(seconds: 1));
                return p;
              });
            }
            n++;
            if (!todas.isCompleted) todas.complete();
            return ultima.stream;
          });
      return (g: g, armazem: armazem, ultima: ultima, todas: todas.future);
    }

    Future<List<int>> tudo(GravadorDireto g) async => (await g.ler(g.inicio, g.fim - g.inicio))!;

    /// Os PCR do gravado sobem sempre (nunca andam para trás nem se repetem).
    void pcrSempreASubir(List<int> gravado) {
      final pcrs = <int>[];
      LeitorTs().ler(gravado, (p) {
        if (p.pcr != null) pcrs.add(p.pcr!);
        return false;
      });
      expect(pcrs.length, greaterThan(100));
      for (var i = 1; i < pcrs.length; i++) {
        expect(pcrs[i], greaterThan(pcrs[i - 1]), reason: 'PCR n.º $i');
      }
    }

    /// O índice de tempo: quanto mais para trás, mais antiga a posição (e vice-versa).
    void indiceMonotono(GravadorDireto g) {
      var antes = g.inicio;
      for (var s = 600; s >= 0; s--) {
        final p = g.posicaoHa(Duration(seconds: s));
        expect(p, greaterThanOrEqualTo(antes), reason: 'posicaoHa(${s}s)');
        antes = p;
      }
      var recuo = g.recuoDe(g.inicio);
      for (var p = g.inicio; p <= g.fim; p += 188 * 37) {
        final r = g.recuoDe(p);
        expect(r, lessThanOrEqualTo(recuo), reason: 'recuoDe($p)');
        recuo = r;
      }
    }

    test('a ligação nova repete os últimos 25 s com os mesmos bytes: continua no byte seguinte', () async {
      // a 1.ª acaba a meio de um pacote; a 2.ª recomeça 25 s (2500 pacotes) antes
      final primeira = tsSintetico(0, 4000).sublist(0, 3999 * 188 + 100);
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(primeira, 7000),
        emPedacos(tsSintetico(1500, 6000), 65536),
      ]);
      final crescimentos = <int>[];
      g.crescimento.listen(crescimentos.add);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      expect(g.fim, 6000 * 188);
      final gravado = await tudo(g);
      expect(gravado, tsSintetico(0, 6000), reason: 'sem duplicados nem buracos');
      pcrSempreASubir(gravado);
      for (var i = 1; i < crescimentos.length; i++) {
        expect(crescimentos[i], greaterThan(crescimentos[i - 1]));
      }
      indiceMonotono(g);
      // o pacote cortado no fim da 1.ª completou-se: o alinhamento continua o da 1.ª
      for (final p in [0, 3999 * 188 + 50, 4500 * 188 + 3]) {
        expect((await g.ler(g.alinhar(p), 1))!.single, 0x47);
      }
      await ultima.close();
      await g.parar();
    });

    test('sem sobreposição nos bytes mas com o PCR contínuo: cose pelo PCR num início de PES', () async {
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(tsSintetico(0, 4000), 65536),
        emPedacos(tsSintetico(1500, 6000, variante: 1), 65536), // outros bytes, os mesmos tempos
      ]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      // o último PCR gravado é o do 3999; o seguinte é o do 4003; o 1.º PES a partir dele, o 4005
      final gravado = await tudo(g);
      expect(gravado, [...tsSintetico(0, 4000), ...tsSintetico(4005, 6000, variante: 1)]);
      pcrSempreASubir(gravado);
      indiceMonotono(g);
      expect(g.alinhar(4000 * 188 - 5), 4000 * 188);
      await ultima.close();
      await g.parar();
    });

    test('uma repetição de ~21 MB (muito para lá do limite da procura): costura exata pelos bytes', () async {
      // 30 s a ~5,7 Mb/s: 112 000 pacotes repetidos (21 MB), com a reserva de 4 MiB a rodar
      final todo = tsSintetico(0, 125000, passo: 24); // ~3750 pacotes/s (~5,6 Mb/s)
      final (:g, :armazem, :ultima, :todas) = comLigacoes([
        emPedacos(todo.sublist(0, 120000 * 188), 65536),
        emPedacos(todo.sublist(8000 * 188), 65536),
      ]);
      var maximo = 0;
      g.crescimento.listen((_) => maximo = math.max(maximo, armazem.bytesEmUso));
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      expect(g.fim, 125000 * 188, reason: 'sem nada repetido');
      final gravado = await tudo(g);
      expect(gravado, todo.sublist(g.inicio), reason: 'contínuo byte a byte');
      expect(maximo, lessThanOrEqualTo(64 * _bloco - g.folgaProcura));
      await ultima.close();
      await g.parar();
    });

    test('bytes diferentes e o PES seguinte antes do PCR seguinte: começa nesse PES (pelo DTS)', () async {
      // o último PES gravado é o 4020 e o último PCR o 4023; o PES 4025 vem antes do PCR 4027
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(tsSintetico(0, 4024), 65536),
        emPedacos(tsSintetico(1500, 6000, variante: 1), 65536),
      ]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final gravado = await tudo(g);
      expect(gravado, [...tsSintetico(0, 4024), ...tsSintetico(4025, 6000, variante: 1)],
          reason: 'pelo PCR seria o 4030: perdia-se a imagem 4025');
      pcrSempreASubir(gravado);
      await ultima.close();
      await g.parar();
    });

    test('uma cauda ambígua (20 pacotes nulos): só vale o encontro com o PCR seguinte maior', () async {
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos([...tsSintetico(0, 4000), ...nulos(20)], 65536),
        emPedacos([
          ...tsSintetico(1500, 2000), ...nulos(25), // os nulos casam aqui primeiro (cedo demais)
          ...tsSintetico(2000, 4000), ...nulos(20), ...tsSintetico(4000, 6000),
        ], 65536),
      ]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final gravado = await tudo(g);
      expect(gravado, [...tsSintetico(0, 4000), ...nulos(20), ...tsSintetico(4000, 6000)]);
      pcrSempreASubir(gravado);
      await ultima.close();
      await g.parar();
    });

    test('o canal recomeça (PCR muito para trás) depois de já se ter largado o começo: alinhamento certo',
        () async {
      final novo = tsSintetico(0, 1000, variante: 2);
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(tsSintetico(13000, 17000), 65536), // PCR de 130 a 170 s
        emPedacos([...tsSintetico(14000, 15500, variante: 1), ...novo], 65536), // velha, e depois 0 s
      ], limite: 100 * 188);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final antes = 4000 * 188;
      final gravado = await tudo(g);
      // grava-se do primeiro PCR do recomeço (o pacote 3), não do que já se tinha largado
      expect(gravado, [...tsSintetico(13000, 17000), ...novo.sublist(3 * 188)]);
      for (final p in [antes, antes + 1, antes + 500 * 188 + 7]) {
        final a = g.alinhar(p);
        expect((await g.ler(a, 1))!.single, 0x47, reason: 'alinhar($p) = $a');
      }
      await ultima.close();
      await g.parar();
    });

    test('uma ligação toda velha não grava nada; a seguinte cose-se pelos bytes', () async {
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(tsSintetico(0, 4000).sublist(0, 3999 * 188 + 100), 65536), // acaba a meio de um pacote
        emPedacos(tsSintetico(1000, 3000, variante: 1), 65536),
        emPedacos(tsSintetico(2000, 6000), 65536),
      ]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final gravado = await tudo(g);
      expect(gravado, tsSintetico(0, 6000));
      indiceMonotono(g);
      // a ligação velha não partiu o alinhamento: o pacote cortado completou-se na 3.ª
      for (final p in [3999 * 188 + 50, 4000 * 188, 5000 * 188 + 7]) {
        expect((await g.ler(g.alinhar(p), 1))!.single, 0x47, reason: 'alinhar($p)');
      }
      await ultima.close();
      await g.parar();
    });

    test('sem PCR legível na ligação nova: grava-a inteira, como antes', () async {
      final nova = tsSintetico(1500, 3000, variante: 1, comPcr: false);
      final (:g, armazem: _, :ultima, :todas) = comLigacoes([
        emPedacos(tsSintetico(0, 4000), 65536),
        emPedacos(nova, 65536),
      ]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      expect(await tudo(g), [...tsSintetico(0, 4000), ...nova]);
      await ultima.close();
      await g.parar();
    });

    test('a ligação nova começa à frente (salto): grava-a desde o início, logo no 1.º pedaço', () async {
      final (:g, :armazem, :ultima, :todas) = comLigacoes([emPedacos(tsSintetico(0, 4000), 65536)]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      expect(g.fim, 4000 * 188);
      final nova = emPedacos(tsSintetico(5000, 6000), 65536);
      ultima.add(nova.first);
      await pumpEventQueue();
      expect(g.fim, 4000 * 188 + 65536, reason: 'decide-se no 1.º pedaço: o direto não espera');
      for (final p in nova.skip(1)) {
        ultima.add(p);
      }
      await pumpEventQueue();
      final gravado = await tudo(g);
      expect(gravado, [...tsSintetico(0, 4000), ...tsSintetico(5000, 6000)]);
      pcrSempreASubir(gravado);
      expect(armazem.bytesEmUso, lessThanOrEqualTo(64 * _bloco));
      await ultima.close();
      await g.parar();
    });

    test('enquanto procura não grava nada (nem conta para a reserva); grava logo que decide', () async {
      final (:g, :armazem, :ultima, :todas) = comLigacoes([emPedacos(tsSintetico(0, 4000), 65536)]);
      final crescimentos = <int>[];
      g.crescimento.listen(crescimentos.add);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final antes = g.fim, emUso = armazem.bytesEmUso, quantos = crescimentos.length;
      final nova = emPedacos(tsSintetico(1500, 6000), 65536);
      // 2500 pacotes repetidos = 470 000 bytes: os primeiros 7 pedaços são só repetição
      for (final p in nova.take(7)) {
        ultima.add(p);
      }
      await pumpEventQueue();
      expect(g.fim, antes, reason: 'nada escrito enquanto procura');
      expect(armazem.bytesEmUso, emUso, reason: 'o que se guarda para procurar fica fora do armazém');
      expect(crescimentos, hasLength(quantos));
      ultima.add(nova[7]); // traz o fim da cauda
      await pumpEventQueue();
      expect(g.fim, 8 * 65536 + 1500 * 188, reason: 'decidiu e escreveu o que vinha depois da cauda');
      for (final p in nova.skip(8)) {
        ultima.add(p);
      }
      await pumpEventQueue();
      expect(await tudo(g), tsSintetico(0, 6000));
      await ultima.close();
      await g.parar();
      expect(armazem.bytesEmUso, 0);
    });

    test('parar() a meio da procura larga o que estava guardado e não escreve nada', () async {
      final (:g, :armazem, :ultima, :todas) = comLigacoes([emPedacos(tsSintetico(0, 4000), 65536)]);
      await g.iniciar();
      await todas;
      await pumpEventQueue();
      final antes = g.fim;
      ultima.add(tsSintetico(1500, 2000));
      await pumpEventQueue();
      expect(g.fim, antes);
      await g.parar();
      expect(armazem.bytesEmUso, 0);
      expect(await g.ler(0, 10), isNull);
    });
  });
}
