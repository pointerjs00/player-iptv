import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/m3u_remoto.dart';
import 'package:player_iptv/protocolos/stalker.dart';
import 'package:player_iptv/protocolos/xtream.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

import '../apoio/servidor_falso.dart';

class _Mede extends Verificador {
  final tempos = <Duration>[];
  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso}) async {
    tempos.add(timeout);
    return ResultadoVerificacao(EstadoV.inconclusivo, 'falso');
  }

  @override
  Duration get pausaReteste => Duration.zero;
}

/// Regista o limite por lista que o serviço pede em cada volta.
class _MedeLimite extends Verificador {
  _MedeLimite() : super(pausaReteste: Duration.zero);
  final limites = <Duration?>[];
  final tempos = <Duration>[];
  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso, Duration? limite}) async {
    limites.add(limite);
    tempos.add(timeout);
    return const ResultadoVerificacao(EstadoV.inconclusivo, 'falso');
  }
}

/// 1.ª volta inconclusiva com um motivo útil; o reteste esgota o tempo por lista.
class _RetesteEsgota extends Verificador {
  _RetesteEsgota() : super(pausaReteste: Duration.zero);
  var voltas = 0;
  @override
  Future<ResultadoVerificacao> verificarComLimite(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso, Duration? limite}) async {
    voltas++;
    if (voltas == 1) {
      return const ResultadoVerificacao(EstadoV.inconclusivo, 'abriu 1 de 3 canais', validade: '2027-10-16');
    }
    return ResultadoVerificacao(EstadoV.inconclusivo, 'tempo esgotado (limite de ${limite!.inSeconds}s por lista)',
        tempoEsgotado: true);
  }
}

/// Uma volta que nunca acaba sozinha (só ao ser cancelada).
class _NuncaAcaba extends Verificador {
  @override
  Future<ResultadoVerificacao> verificarUmaVez(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso}) async {
    while (true) {
      cancelamento?.verificar();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('efeito'));
  tearDown(() {
    Preferencias.atual = Preferencias.omissao();
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  test('o tempo limite das definições chega ao verificador (1.ª volta; o dobro na 2.ª)', () async {
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]);
    final prefs = Preferencias.omissao()..timeoutVerificacao = 20;
    final f = _Mede();
    final s = ServicoVerificacao(bib, verificador: f, preferencias: prefs);
    await s.verificar(bib.listas.first);
    expect(f.tempos, [const Duration(seconds: 20), const Duration(seconds: 40)]);
    // mudar nas definições vale já para a verificação seguinte
    f.tempos.clear();
    prefs.timeoutVerificacao = 5;
    await s.verificar(bib.listas.first);
    expect(f.tempos.first, const Duration(seconds: 5));
  });

  test('sem preferências dadas, usa as da app (8 s por omissão)', () async {
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]);
    final f = _Mede();
    await ServicoVerificacao(bib, verificador: f).verificar(bib.listas.first);
    expect(f.tempos.first, const Duration(seconds: 8));
  });

  test('o tempo limite por lista chega ao verificador; no reteste é o dobro, como o dos canais', () async {
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]);
    final prefs = Preferencias.omissao()
      ..tempoLimiteLista = 10
      ..timeoutVerificacao = 6;
    final f = _MedeLimite();
    await ServicoVerificacao(bib, verificador: f, preferencias: prefs).verificar(bib.listas.first);
    expect(f.limites, [const Duration(seconds: 10), const Duration(seconds: 20)]);
    expect(f.tempos, [const Duration(seconds: 6), const Duration(seconds: 12)]);
  });

  test('um reteste que esgota o tempo deixa o resultado da 1.ª volta, com o seu motivo', () async {
    final bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!)]);
    final f = _RetesteEsgota();
    await ServicoVerificacao(bib, verificador: f, preferencias: Preferencias.omissao()).verificar(bib.listas.first);
    expect(f.voltas, 2);
    final u = bib.listas.first.ultima!;
    expect(u.estado, 'inconclusivo');
    expect(u.motivo, 'abriu 1 de 3 canais');
    expect(u.validade, '2027-10-16');
  });

  test('o tempo limite por lista esgotado dá inconclusivo "por lista" (limite do verificador)', () async {
    final r = await _NuncaAcaba().verificarComLimite(
        Conta('x', Tipo.m3u, 'http://s/lista.m3u'), const ['rtp1'],
        limite: const Duration(milliseconds: 200));
    expect(r.estado, EstadoV.inconclusivo);
    expect(r.tempoEsgotado, isTrue);
    expect(r.motivo, contains('por lista'));
    expect(r.motivo, contains('0.2s'));
  });

  group('user-agent personalizado', () {
    final canal = const Canal(id: '7', nome: 'RTP 1', grupo: 'G', url: 'http://s/1.ts');
    final xt = Conta('x', Tipo.xtream, 'http://s:80/get.php?username=u&password=p', utilizador: 'u', password: 'p');
    final m3u = Conta('m', Tipo.m3u, 'http://s/lista.m3u');

    test('sem personalização: o VLC por omissão', () async {
      expect((await Xtream().fonte(xt, canal)).headers['User-Agent'], uaVlc);
      expect((await M3uRemoto().fonte(m3u, canal)).headers['User-Agent'], uaVlc);
    });

    test('M3U e Xtream usam o personalizado; o Stalker mantém o MAG', () async {
      Preferencias.atual = Preferencias.omissao()..userAgent = 'MeuPlayer/2.0';
      expect((await Xtream().fonte(xt, canal)).headers['User-Agent'], 'MeuPlayer/2.0');
      expect((await M3uRemoto().fonte(m3u, canal)).headers['User-Agent'], 'MeuPlayer/2.0');
      expect(macHeaders('00:1A:79:00:00:01', 'http://s/c/')['User-Agent'], uaMag);
    });

    test('um user-agent próprio do canal na M3U continua a ganhar', () async {
      Preferencias.atual = Preferencias.omissao()..userAgent = 'MeuPlayer/2.0';
      const c = Canal(id: '7', nome: 'x', grupo: 'G', url: 'http://s/1.ts', userAgent: 'DoCanal');
      expect((await M3uRemoto().fonte(m3u, c)).headers['User-Agent'], 'DoCanal');
    });

    test('vai nos pedidos HTTP da lista (Xtream e M3U)', () async {
      Preferencias.atual = Preferencias.omissao()..userAgent = 'MeuPlayer/2.0';
      final srv = ServidorFalso((p) => p.uri.path == '/lista.m3u'
          ? (200, '#EXTM3U\n#EXTINF:-1 group-title="G",RTP 1\nhttp://s/1.ts\n')
          : (200, {'user_info': {'auth': 1, 'status': 'Active'}}));
      await srv.iniciar();
      addTearDown(srv.parar);
      await M3uRemoto().abrir(Conta('m', Tipo.m3u, '${srv.url}/lista.m3u'));
      try {
        await Xtream().abrir(Conta('x', Tipo.xtream, '${srv.url}/get.php?username=u&password=p',
            utilizador: 'u', password: 'p'));
      } catch (_) {/* só interessa o cabeçalho */}
      expect(srv.pedidos, isNotEmpty);
      for (final p in srv.pedidos) {
        expect(p.headers.value('user-agent'), 'MeuPlayer/2.0');
      }
    });
  });
}
