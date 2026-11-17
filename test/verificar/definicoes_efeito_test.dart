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
