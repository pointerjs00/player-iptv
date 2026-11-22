import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/stalker.dart';
import 'package:player_iptv/protocolos/xtream.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/canais_teste.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/verificador.dart';
import 'package:player_iptv/verificar/video.dart';

import '../apoio/servidor_falso.dart';

/// 2 pacotes TS válidos (sync 0x47 a cada 188 bytes), repetidos.
String ts([int pacotes = 20]) {
  final b = StringBuffer();
  for (var i = 0; i < pacotes; i++) {
    b.write(String.fromCharCode(0x47));
    b.write('x' * 187);
  }
  return b.toString();
}

Future<ResultadoVerificacao?> _semDns(String _) async => null;

void main() {
  late ServidorFalso srv;
  setUp(() async {
    srv = ServidorFalso((_) => (404, ''));
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  group('perfis dos canais', () {
    test('candidatos: portugueses primeiro e nomes curtos; exclusões e PT obrigatório', () {
      final rtp = perfisCanais['rtp1']!;
      expect(candidatos(rtp, ['RTP 1 HD', 'PT: RTP 1', 'RTP 1 Açores', 'RTP 11', 'PT: RTP1 FHD'], (s) => s),
          ['PT: RTP 1', 'PT: RTP1 FHD', 'RTP 1 HD']);
      final sport = perfisCanais['sporttv1']!;
      expect(candidatos(sport, ['Sport TV 1', 'PT: SPORT TV 1', 'PT: SPORT TV 1 PFC'], (s) => s), ['PT: SPORT TV 1']);
      final dazn = perfisCanais['dazn1']!;
      expect(candidatos(dazn, ['PT: DAZN 1', 'PT: DAZN 1 PPV', 'ES: DAZN 1'], (s) => s), ['PT: DAZN 1']);
    });
    test('tabela de nomes: separadores e "Um"', () {
      bool casa(String perfil, String nome) => candidatos(perfisCanais[perfil]!, [nome], (s) => s).isNotEmpty;
      for (final n in ['RTP 1', 'RTP-1', 'RTP.1', 'RTP_1', 'RTP | 1', 'RTP1', 'RTP Um', 'PT: RTP-1 HD']) {
        expect(casa('rtp1', n), isTrue, reason: n);
      }
      for (final n in ['RTP 11', 'RTP Umbria', 'RTP 1 Açores', 'RTP-1 Madeira', 'RTP 1 Internacional', 'RTP 1 África',
        'RTP 2', 'XRTP 1']) {
        expect(casa('rtp1', n), isFalse, reason: n);
      }
      for (final n in ['PT: SPORT.TV 1', 'PT: Sport-TV1', 'PT: Sport TV Um', 'PT | SPORT_TV 1', 'PT: SPORTTV 1']) {
        expect(casa('sporttv1', n), isTrue, reason: n);
      }
      for (final n in ['PT: SPORT TV 11', 'PT: SPORT TV 1 PFC', 'PT: SPORT TV 2', 'PT: SPORT TV Umbra', 'SPORT TV 1']) {
        expect(casa('sporttv1', n), isFalse, reason: n);
      }
      for (final n in ['PT: DAZN-1', 'PT: DAZN.1', 'PT: DAZN Um', 'PT: DAZN | 1', 'PT: DAZN1']) {
        expect(casa('dazn1', n), isTrue, reason: n);
      }
      for (final n in ['PT: DAZN 11', 'PT: DAZN 1 PPV', 'PT: DAZN 1 EVENT', 'PT: DAZN 2', 'ES: DAZN 1']) {
        expect(casa('dazn1', n), isFalse, reason: n);
      }
    });
    test('grupo de Portugal aceita sem PT no nome; Brasil não conta', () {
      final sport = perfisCanais['sporttv1']!;
      final itens = [('Sport TV 1', 'Portugal'), ('Sport TV 1 ', 'Brasil'), ('Sport TV 1  ', 'PT | Desporto'),
        ('Sport TV 1   ', 'Portugal/Brasil'), ('Sport TV 1    ', 'BR Desporto'), ('Sport TV 1     ', 'Português')];
      final r = candidatos(sport, itens, (i) => i.$1, null, (i) => i.$2).map((i) => i.$2).toSet();
      expect(r, {'Portugal', 'PT | Desporto', 'Português'});
      final rtp = perfisCanais['rtp1']!;
      final o = candidatos(rtp, [('RTP 1', 'Geral'), ('RTP 1 HD', 'Portugal')], (i) => i.$1, null, (i) => i.$2);
      expect(o.first.$2, 'Portugal');
    });
    test('perfisDe', () {
      expect(perfisDe(['dazn1', 'rtp1']).map((p) => p.id), ['rtp1', 'dazn1']);
      expect(perfisDe(['xpto']).map((p) => p.id), ['rtp1']);
    });
  });

  group('leitura do stream', () {
    test('MPEG-TS é vídeo; HTML não; HLS segue a playlist', () async {
      srv.responder = (p) => switch (p.uri.path) {
            '/ts' => (200, ts()),
            '/html' => (200, '<html>${'x' * 500}</html>'),
            '/master.m3u8' => (200, '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nsub/var.m3u8\n'),
            '/sub/var.m3u8' => (200, '#EXTM3U\n#EXTINF:6,\nseg1.ts\n'),
            '/sub/seg1.ts' => (200, ts()),
            '/curto' => (200, 'abc'),
            '/limite' => (459, ''),
            '/proibido' => (403, ''),
            _ => (404, ''),
          };
      Future<EstadoV> e(String c, {bool inc = false}) async =>
          (await lerStream('${srv.url}$c', const {}, stream401Inc: inc)).estado;
      expect(await e('/ts'), EstadoV.funciona);
      expect(await e('/master.m3u8'), EstadoV.funciona);
      expect(await e('/html'), EstadoV.naoFunciona);
      expect(await e('/curto'), EstadoV.inconclusivo);
      expect(await e('/limite'), EstadoV.inconclusivo);
      expect(await e('/proibido'), EstadoV.naoFunciona);
      expect(await e('/proibido', inc: true), EstadoV.inconclusivo);
      expect(await e('/naoexiste'), EstadoV.naoFunciona);
    });
    test('eVideo e syncTs', () {
      expect(syncTs(ts().codeUnits), 0);
      expect(eVideo(ts(1).codeUnits), isFalse); // curto demais
    });
  });

  group('validade', () {
    test('texto do campo phone (Stalker)', () {
      expect(validadeDoTexto('February 3, 2027, 12:42 am'), '2027-02-03');
      expect(validadeDoTexto('Unlimited'), 'sem limite');
      expect(validadeDoTexto('February 30, 2027'), '');
      expect(validadeDoTexto('+351 912 345 678'), '');
    });
    test('exp_date (Xtream)', () {
      expect(Xtream.validadeXtream({}), '');
      expect(Xtream.validadeXtream({'exp_date': null}), 'sem limite');
      expect(Xtream.validadeXtream({'exp_date': '0'}), 'sem limite');
      expect(Xtream.validadeXtream({'exp_date': 'x'}), '');
      expect(Xtream.validadeXtream({'exp_date': '${DateTime(2027, 10, 16, 12).millisecondsSinceEpoch ~/ 1000}'}),
          '2027-10-16');
    });
  });

  group('verificação de uma conta Xtream', () {
    Resposta painel(HttpRequest p, {String auth = '1', String exp = '0', bool temRtp = true, int streamStatus = 200}) {
      if (p.uri.path == '/player_api.php') {
        return switch (p.uri.queryParameters['action']) {
          null => (200, {'user_info': {'auth': auth, 'status': 'Active', 'exp_date': exp}}),
          'get_live_categories' => (200, [{'category_id': '1', 'category_name': 'PT'}]),
          'get_live_streams' => (200, [
              if (temRtp) {'stream_id': 1, 'name': 'PT: RTP 1 HD', 'category_id': '1'},
              {'stream_id': 2, 'name': 'PT: DAZN 1', 'category_id': '1'},
            ]),
          _ => (404, ''),
        };
      }
      if (p.uri.path.startsWith('/live/')) return (streamStatus, streamStatus == 200 ? ts() : '');
      return (404, '');
    }

    Conta conta() => Conta('x', Tipo.xtream, srv.url, utilizador: 'u', password: 'p');
    final v = Verificador(dns: _semDns, espera: Duration.zero, pausaReteste: Duration.zero);

    test('funciona e traz a validade', () async {
      final exp = DateTime(2030, 1, 2, 12).millisecondsSinceEpoch ~/ 1000;
      srv.responder = (p) => painel(p, exp: '$exp');
      final r = await v.verificar(conta(), ['rtp1']);
      expect((r.estado, r.canal, r.validade), (EstadoV.funciona, 'PT: RTP 1 HD', '2030-01-02'));
      expect(paraUltima(r).motivo, 'abriu PT: RTP 1 HD');
    });

    test('autenticação recusada e conta expirada são prova', () async {
      srv.responder = (p) => painel(p, auth: '0');
      expect((await v.verificar(conta(), ['rtp1'])).estado, EstadoV.naoFunciona);
      srv.responder = (p) => painel(p, exp: '1000000000'); // 2001
      final r = await v.verificar(conta(), ['rtp1']);
      expect(r.estado, EstadoV.naoFunciona);
      expect(r.motivo, startsWith('conta expirada'));
    });

    test('canal que não existe na conta; vários canais: basta um', () async {
      srv.responder = (p) => painel(p, temRtp: false);
      final r1 = await v.verificar(conta(), ['rtp1']);
      expect((r1.estado, r1.motivo), (EstadoV.naoFunciona, 'RTP 1 não existe na conta'));
      final r2 = await v.verificar(conta(), ['rtp1', 'dazn1']);
      expect(r2.estado, EstadoV.funciona);
      expect(r2.canais.map((c) => (c['id'], c['estado'])), [('rtp1', 'nao_funciona'), ('dazn1', 'funciona')]);
    });

    test('o passo diz em que canal de teste vai ("canal 2/2 · ..."), para o Gestor mostrar', () async {
      srv.responder = (p) => painel(p, temRtp: false);
      final avisos = <String>[];
      await v.verificar(conta(), ['rtp1', 'dazn1'], aviso: avisos.add);
      expect(avisos.where((a) => a.startsWith('canal 2/2 · DAZN 1 · variante 1/')), isNotEmpty, reason: '$avisos');
      expect(avisos.where((a) => a.startsWith('canal 1/')), isEmpty, reason: 'RTP 1 não existe: não há variantes');
    });

    test('limite de ligações fica inconclusivo (com 2.ª volta)', () async {
      srv.responder = (p) => painel(p, streamStatus: 459);
      final r = await v.verificar(conta(), ['rtp1']);
      expect(r.estado, EstadoV.inconclusivo);
      // 1.ª volta + 2.ª volta, cada uma com 2 leituras
      expect(srv.pedidos.where((p) => p.uri.path.startsWith('/live/')), hasLength(4));
    });

    test('a 2.ª volta usa os canais da 1.ª e só repete o canal de teste inconclusivo', () async {
      // RTP 1 não existe (prova); o DAZN 1 dá erro 500 (INC, pode mudar)
      srv.responder = (p) => painel(p, temRtp: false, streamStatus: 500);
      final r = await v.verificar(conta(), ['rtp1', 'dazn1']);
      expect(r.estado, EstadoV.inconclusivo);
      final api = srv.pedidos.where((p) => p.uri.path == '/player_api.php');
      expect(api.where((p) => p.uri.queryParameters['action'] == 'get_live_streams'), hasLength(1));
      // o DAZN 1: 2 leituras em cada volta
      expect(srv.pedidos.where((p) => p.uri.path.startsWith('/live/')), hasLength(4));
      expect(r.canais.map((c) => (c['id'], c['estado'])), [('rtp1', 'nao_funciona'), ('dazn1', 'inconclusivo')]);
    });

    test('"conta sem canais" não tem 2.ª volta (daqui a um minuto continua sem canais)', () async {
      srv.responder = (p) => p.uri.queryParameters['action'] == 'get_live_streams' ? (200, []) : painel(p);
      final r = await v.verificar(conta(), ['rtp1']);
      expect((r.estado, r.motivo, r.repeticao), (EstadoV.inconclusivo, 'conta sem canais', Repeticao.inutil));
      expect(srv.pedidos.where((p) => p.uri.path == '/player_api.php' && p.uri.queryParameters['action'] == null),
          hasLength(1));
    });

    test('o tempo esgota-se depois de um canal de teste abrir: funciona', () async {
      srv.responder = (p) => painel(p);
      // o RTP 1 abre; o DAZN 1 nunca responde
      final v2 = Verificador(dns: _semDns, espera: Duration.zero, pausaReteste: Duration.zero,
          ler: (url, headers, {timeout = const Duration(seconds: 8), cancelamento, stream401Inc = false}) async {
        if (url.contains('/1.')) return const ResultadoVerificacao(EstadoV.funciona, 'vídeo recebido');
        while (true) {
          cancelamento?.verificar();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      final r = await runZoned(
          () => v2.verificarComLimite(conta(), ['rtp1', 'dazn1'], limite: const Duration(milliseconds: 400)),
          zoneValues: {progressoZona: ProgressoVerificacao()});
      expect(r.estado, EstadoV.funciona);
      expect(r.canais.map((c) => (c['id'], c['estado'])), [('rtp1', 'funciona'), ('dazn1', 'inconclusivo')]);
    });

    test('limite de ligações pede pausa antes da 2.ª volta; um erro 500 não', () {
      expect(classificarFalha(ErroHttp(459, 'x')).repeticao, Repeticao.depoisDePausa);
      expect(classificarFalha(ErroHttp(500, 'x')).repeticao, Repeticao.imediata);
    });

    test('DNS inexistente é prova', () async {
      final v2 = Verificador(dns: (_) async => const ResultadoVerificacao(EstadoV.naoFunciona, 'DNS: x não existe'));
      expect((await v2.verificar(conta(), ['rtp1'])).estado, EstadoV.naoFunciona);
    });
  });

  test('portal Stalker inexistente (todos os endpoints 404) é prova', () async {
    final v = Verificador(dns: _semDns, espera: Duration.zero, pausaReteste: Duration.zero);
    final r = await v.verificar(Conta('x', Tipo.stalker, '${srv.url}/c/', mac: '00:1A:79:00:00:01'), ['rtp1']);
    expect((r.estado, r.motivo), (EstadoV.naoFunciona, 'portal não encontrado'));
    expect(limparCmd('ffrt http://a'), 'http://a');
  });
}
