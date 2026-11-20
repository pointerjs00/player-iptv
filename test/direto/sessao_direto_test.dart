import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/armazem.dart';
import 'package:player_iptv/direto/gravador.dart';
import 'package:player_iptv/direto/sessao_direto.dart';
import 'package:player_iptv/modelo/canal.dart';

const _origem = 'http://exemplo.invalid/live/utilizador/segredo/1.ts';

/// Um MPEG-TS falso: 0x47 a cada 188 bytes.
List<int> _ts(int n) => List<int>.generate(n, (i) => i % 188 == 0 ? 0x47 : (i * 7 + 1) & 0x3f);

/// A origem falsa: cada ligação é um StreamController que o teste alimenta.
class _Origem {
  final ligacoes = <StreamController<List<int>>>[];
  final pedidos = <(Uri, Map<String, String>)>[];
  final _ligou = StreamController<StreamController<List<int>>>.broadcast();

  /// As ligações abertas agora (o gravador a ler) e o máximo ao mesmo tempo.
  int abertas = 0;
  int maximoAbertas = 0;

  /// Se dado, a ligação falha com isto.
  Object? falha;

  Future<Stream<List<int>>> abrir(Uri u, Map<String, String> c) async {
    pedidos.add((u, c));
    final f = falha;
    if (f != null) throw f;
    final s = StreamController<List<int>>(onListen: () {
      abertas++;
      if (abertas > maximoAbertas) maximoAbertas = abertas;
    }, onCancel: () => abertas--);
    ligacoes.add(s);
    _ligou.add(s);
    return s.stream;
  }

  Future<StreamController<List<int>>> proxima() =>
      ligacoes.isNotEmpty ? Future.value(ligacoes.last) : _ligou.stream.first;
}

void main() {
  late Directory tmp;
  late _Origem origem;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sessao_direto_');
    origem = _Origem();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SessaoGravada nova() => SessaoGravada(
        pastaBase: () async => tmp,
        reservaBytes: 256 * 1024,
        tamanhoBloco: 64 * 1024,
        abrirOrigem: origem.abrir,
        esperar: (_) async {},
      );

  group('gravavel', () {
    test('só diretos progressivos', () {
      expect(gravavel('http://h:8080/live/u/p/1.ts'), isTrue);
      expect(gravavel('http://h/u/p/123'), isTrue, reason: 'Xtream sem extensão');
      expect(gravavel('http://h/play/live.php?mac=x&stream=1&extension=ts'), isTrue);
      expect(gravavel('https://h/canal/index.m3u8'), isFalse, reason: 'HLS');
      expect(gravavel('https://h/canal/INDEX.M3U8?token=1'), isFalse);
      expect(gravavel('http://h/play/live.php?stream=1&extension=m3u8'), isFalse);
      expect(gravavel('http://h/movie/u/p/1.mp4'), isFalse, reason: 'filme Xtream');
      expect(gravavel('http://h/series/u/p/2.ts'), isFalse, reason: 'série Xtream');
      expect(gravavel('http://h/filmes/a.mkv'), isFalse);
      expect(gravavel('http://h/canal/manifest.mpd'), isFalse, reason: 'DASH');
      expect(gravavel('http://h/timeshift/u/p/60/2026-11-20:20-00/1.ts'), isFalse, reason: 'timeshift');
      expect(gravavel('http://h/xc/movie/u/p/1.ts'), isFalse, reason: 'filme com prefixo');
      expect(gravavel('rtmp://h/live'), isFalse);
      expect(gravavel(''), isFalse);
    });
  });

  test('um TS abre no URL local (nunca o de origem), grava na pasta da sessão e fechar apaga tudo', () async {
    final s = nova();
    final aberta = s.abrir(const FonteVideo(_origem, {'User-Agent': 'Teste'}));
    final l = await origem.proxima();
    l.add(_ts(188 * 10));
    final url = await aberta;
    expect(url, isNotNull);
    expect(url!.host, '127.0.0.1');
    expect(url.toString(), isNot(contains('exemplo.invalid')));
    expect(url.toString(), isNot(contains('segredo')));
    expect(url, s.urlDireto);
    expect(origem.pedidos.single.$1.toString(), _origem);
    expect(origem.pedidos.single.$2, {'User-Agent': 'Teste'});
    final pastas = tmp.listSync().whereType<Directory>().toList();
    expect(pastas, hasLength(1), reason: 'uma pasta por sessão');
    expect(s.fim, 188 * 10);

    // o motor lê o direto pelo servidor local
    final c = HttpClient();
    final r = await (await c.getUrl(s.urlDesde(0))).close();
    expect(r.statusCode, 200);
    final primeiro = await r.first;
    expect(primeiro.first, 0x47);
    c.close(force: true);

    await s.fechar();
    expect(pastas.single.existsSync(), isFalse, reason: 'a pasta é apagada ao fechar');
    await expectLater(Socket.connect(url.host, url.port), throwsA(isA<SocketException>()),
        reason: 'o servidor fechou');
    await s.fechar(); // outra vez não faz mal
  });

  test('uma playlist HLS (pelo conteúdo) não é gravada: devolve null e apaga a pasta', () async {
    final s = nova();
    final aberta = s.abrir(const FonteVideo('http://h/play/live.php?stream=1'));
    final l = await origem.proxima();
    l.add(utf8.encode('#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:6,\nseg1.ts\n'));
    await l.close();
    expect(await aberta, isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('fechar a meio do abrir: abrir dá null e não fica nada no disco', () async {
    final s = nova();
    final aberta = s.abrir(const FonteVideo(_origem));
    await origem.proxima();
    await s.fechar();
    expect(await aberta, isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('o gravador desiste antes de haver dados: abrir falha sem o URL de origem', () async {
    final s = nova();
    origem.falha = const SocketException('ligação recusada a $_origem');
    final erros = <ErroGravador>[];
    final aberta = s.abrir(const FonteVideo(_origem));
    s.erros.listen(erros.add);
    Object? falhou;
    try {
      await aberta;
    } catch (e) {
      falhou = e;
    }
    expect(falhou, isA<ErroSessaoDireto>());
    expect('$falhou', isNot(contains('exemplo.invalid')));
    expect('$falhou', isNot(contains('segredo')));
    for (final e in erros) {
      expect(e.mensagem, isNot(contains('exemplo.invalid')));
    }
    await s.fechar();
    expect(tmp.listSync(), isEmpty);
  });

  test('os erros e o crescimento do gravador chegam pela sessão', () async {
    final s = nova();
    final aberta = s.abrir(const FonteVideo(_origem));
    final l = await origem.proxima();
    l.add(_ts(188 * 4));
    await aberta;
    final cresceu = s.crescimento.first;
    l.add(_ts(188));
    expect(await cresceu, 188 * 5);
    final erro = s.erros.first;
    await l.close(); // a origem fechou: o gravador volta a ligar
    expect((await erro).desistiu, isFalse);
    await s.fechar();
  });

  test('cada religação do gravador pede um link novo (renovar)', () async {
    final s = nova();
    var renovados = 0;
    final aberta = s.abrir(const FonteVideo(_origem, {'User-Agent': 'Teste'}), renovar: () async {
      renovados++;
      return FonteVideo('http://exemplo.invalid/play/novo$renovados.ts', const {'Cookie': 'novo'});
    });
    final l = await origem.proxima();
    l.add(_ts(188 * 4));
    await aberta;
    final religou = origem._ligou.stream.first;
    await l.close(); // a origem cortou
    await religou;
    expect(renovados, 1);
    expect(origem.pedidos.map((p) => p.$1.path), ['/live/utilizador/segredo/1.ts', '/play/novo1.ts']);
    expect(origem.pedidos.last.$2, {'Cookie': 'novo'});
    await s.fechar();
  });

  test('quando não serve, a ligação do gravador já fechou ao devolver null (nunca duas na origem)', () async {
    final s = nova();
    final aberta = s.abrir(const FonteVideo('http://h/live/u/p/1'));
    final l = await origem.proxima();
    // um ficheiro MP4 que não acaba: a ligação fica aberta até o gravador a largar
    l.add([0, 0, 0, 0x20, ...'ftypisom'.codeUnits, ...List<int>.filled(1000, 1)]);
    expect(await aberta, isNull);
    expect(origem.abertas, 0, reason: 'o player pode abrir a origem: o gravador já a largou');
    expect(origem.maximoAbertas, 1);
    expect(tmp.listSync(), isEmpty);
  });

  group('espaço reservado conforme o espaço livre', () {
    const gb = 1 << 30, mb = 1 << 20;

    SessaoGravada comLivre(int? livre, {int reserva = 2 * gb, List<Directory>? medidas}) => SessaoGravada(
          pastaBase: () async => tmp,
          reservaBytes: reserva,
          tamanhoBloco: 64 * 1024,
          abrirOrigem: origem.abrir,
          esperar: (_) async {},
          espacoLivre: (d) async {
            medidas?.add(d);
            return livre;
          },
        );

    test('com espaço para a reserva e 1 GB de margem: a reserva toda, sem aviso', () async {
      final medidas = <Directory>[];
      final s = comLivre(4 * gb, medidas: medidas);
      final aberta = s.abrir(const FonteVideo(_origem));
      (await origem.proxima()).add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      expect(s.reservaEfetiva, 2 * gb);
      expect(s.aviso, isNull);
      expect(medidas.first.path, tmp.path, reason: 'mede-se onde se grava');
      await s.fechar();
    });

    test('espaço livre < reserva + 1 GB: a reserva baixa para o que couber e avisa quanto', () async {
      final s = comLivre(gb + 700 * mb);
      final aberta = s.abrir(const FonteVideo(_origem));
      (await origem.proxima()).add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      expect(s.reservaEfetiva, 700 * mb);
      expect(s.aviso, 'Pouco espaço: o recuo fica com 700 MB');
      await s.fechar();
    });

    test('o mínimo de 256 MiB ainda grava', () async {
      final s = comLivre(gb + 256 * mb);
      final aberta = s.abrir(const FonteVideo(_origem));
      (await origem.proxima()).add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      expect(s.reservaEfetiva, 256 * mb);
      expect(s.aviso, 'Pouco espaço: o recuo fica com 256 MB');
      await s.fechar();
    });

    test('sem espaço nem para 256 MiB: grava em memória (128 MiB), avisa e não cria pasta nenhuma', () async {
      final base = Directory('${tmp.path}/direto');
      final s = SessaoGravada(
        pastaBase: () async => base,
        reservaBytes: 2 * gb,
        tamanhoBloco: 64 * 1024,
        tamanhoBlocoMemoria: 64 * 1024,
        abrirOrigem: origem.abrir,
        esperar: (_) async {},
        espacoLivre: (_) async => gb + 200 * mb,
      );
      final aberta = s.abrir(const FonteVideo(_origem));
      (await origem.proxima()).add(_ts(188 * 4));
      final url = await aberta;
      expect(url, isNotNull, reason: 'o recuo continua, pelo mesmo servidor local');
      expect(s.aviso, 'Pouco espaço: o recuo fica em memória (cerca de 2 min em HD)');
      expect(s.emMemoria, isTrue);
      expect(s.reservaEfetiva, 128 * mb);
      expect(s.armazem, isA<ArmazemMemoria>());
      expect(base.existsSync(), isFalse, reason: 'nem a pasta base se cria');
      expect(tmp.listSync(), isEmpty);
      // o motor lê o direto em memória pelo servidor local
      final c = HttpClient();
      final r = await (await c.getUrl(s.urlDesde(0))).close();
      expect((await r.first).first, 0x47);
      c.close(force: true);
      await s.fechar();
      expect((s.armazem as ArmazemMemoria?)?.bytesEmUso ?? 0, 0);
    });

    test('o recuo em Memória: anel em RAM desde o começo, sem medir o espaço nem tocar no disco', () async {
      var medidas = 0;
      var pedidaPasta = false;
      final s = SessaoGravada(
        pastaBase: () async {
          pedidaPasta = true;
          return tmp;
        },
        reservaBytes: 256 * 1024,
        memoria: true,
        tamanhoBlocoMemoria: 64 * 1024,
        abrirOrigem: origem.abrir,
        esperar: (_) async {},
        espacoLivre: (_) async {
          medidas++;
          return 0;
        },
      );
      final aberta = s.abrir(const FonteVideo(_origem));
      final l = await origem.proxima();
      l.add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      expect((s.emMemoria, s.aviso, s.reservaEfetiva), (true, null, 256 * 1024));
      final memoria = s.armazem! as ArmazemMemoria;
      // muito mais do que a reserva: nunca passa dela
      for (var i = 0; i < 20; i++) {
        final cresceu = s.crescimento.first;
        l.add(_ts(64 * 1024));
        await cresceu;
        expect(memoria.bytesEmUso, lessThanOrEqualTo(256 * 1024));
      }
      expect(medidas, 0);
      expect(pedidaPasta, isFalse);
      expect(tmp.listSync(), isEmpty);
      await s.fechar();
    });

    test('não se sabe o espaço (null): a reserva toda', () async {
      final s = comLivre(null);
      final aberta = s.abrir(const FonteVideo(_origem));
      (await origem.proxima()).add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      expect(s.reservaEfetiva, 2 * gb);
      expect(s.aviso, isNull);
      expect(s.ligouOrigem, isTrue);
      await s.fechar();
    });

    test('o espaço acaba a meio: o erro semEspaco chega pela sessão', () async {
      var livre = 4 * gb;
      final s = SessaoGravada(
        pastaBase: () async => tmp,
        reservaBytes: 256 * 1024,
        tamanhoBloco: 64 * 1024,
        abrirOrigem: origem.abrir,
        esperar: (_) async {},
        espacoLivre: (_) async => livre,
      );
      final aberta = s.abrir(const FonteVideo(_origem));
      final l = await origem.proxima();
      l.add(_ts(188 * 4));
      expect(await aberta, isNotNull);
      livre = 100 * mb;
      final erro = s.erros.first;
      l.add(_ts(64 * 1024));
      final e = await erro;
      expect(e.semEspaco, isTrue);
      expect(e.desistiu, isTrue);
      await pumpEventQueue();
      expect(origem.abertas, 0, reason: 'o gravador larga a origem');
      await s.fechar();
      expect(tmp.listSync(), isEmpty);
    });
  });
}
