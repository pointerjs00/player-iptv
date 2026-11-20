import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

  /// Se dado, a ligação falha com isto.
  Object? falha;

  Future<Stream<List<int>>> abrir(Uri u, Map<String, String> c) async {
    pedidos.add((u, c));
    final f = falha;
    if (f != null) throw f;
    final s = StreamController<List<int>>();
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
}
