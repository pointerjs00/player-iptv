import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/protocolo.dart';
import 'package:player_iptv/protocolos/stalker.dart';
import 'package:player_iptv/protocolos/xtream.dart';
import 'package:player_iptv/rede/http.dart';

import '../apoio/servidor_falso.dart';

const mac = '00:1A:79:00:00:01';

void main() {
  late ServidorFalso srv;
  setUp(() async {
    srv = ServidorFalso((_) => (404, 'não'));
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  group('Xtream', () {
    Resposta api(HttpRequest p, {String auth = '1', Object formatos = const ['ts', 'm3u8']}) {
      if (p.uri.path != '/player_api.php') return (404, '');
      return switch (p.uri.queryParameters['action']) {
        null => (200, {'user_info': {'auth': auth, 'status': 'Active', 'allowed_output_formats': formatos}}),
        'get_live_categories' => (200, [
            {'category_id': '2', 'category_name': 'Desporto'},
            {'category_id': '1', 'category_name': 'Portugal'},
            {'category_id': '9', 'category_name': 'Vazia'},
          ]),
        'get_live_streams' => (200, [
            {'stream_id': 10, 'name': 'RTP 1', 'category_id': '1', 'stream_icon': 'http://l/1.png'},
            {'stream_id': 11, 'name': 'Sport TV 1', 'category_id': '2'},
            {'stream_id': 12, 'name': 'Sem categoria', 'category_id': '77'},
            {'name': 'sem id'},
          ]),
        _ => (404, ''),
      };
    }

    test('grupos pela ordem do painel e links ts/m3u8', () async {
      srv.responder = api;
      final c = Conta('x', Tipo.xtream, '${srv.url}/get.php?username=u&password=p', utilizador: 'u 1', password: 'p');
      final x = Xtream();
      final conteudo = await x.abrir(c);
      expect(conteudo.grupos, ['Desporto', 'Portugal', 'Sem grupo']);
      expect(conteudo.canais.map((c) => c.nome), ['RTP 1', 'Sport TV 1', 'Sem categoria']);
      expect(conteudo.canais.first.logo, 'http://l/1.png');
      final f = await x.fonte(c, conteudo.canais.first);
      expect(f.url, '${srv.url}/live/u%201/p/10.ts');
      srv.responder = (p) => api(p, formatos: 'm3u8');
      await x.abrir(c);
      expect((await x.fonte(c, conteudo.canais.first)).url, endsWith('/10.m3u8'));
    });

    test('autenticação recusada', () async {
      srv.responder = (p) => api(p, auth: '0');
      final c = Conta('x', Tipo.xtream, srv.url, utilizador: 'u', password: 'p');
      expect(() => Xtream().abrir(c), throwsA(isA<ErroLista>().having((e) => e.mensagem, 'm', 'autenticação recusada')));
    });

    test('extensão', () {
      expect(Xtream.extensao({}), 'ts');
      expect(Xtream.extensao({'allowed_output_formats': ['m3u8']}), 'm3u8');
      expect(Xtream.extensao({'allowed_output_formats': 'ts,m3u8'}), 'ts');
    });
  });

  group('Stalker', () {
    Resposta portal(HttpRequest p, {bool todos = true, bool linkVazio = false}) {
      // só o 2.º endpoint existe (o 1.º dá 404)
      if (p.uri.path != '/stalker_portal/c/portal.php') return (404, '');
      expect(p.headers.value('cookie'), contains('mac=$mac'));
      final q = p.uri.queryParameters;
      return switch (q['action']) {
        'handshake' => (200, {'js': {'token': 'T1'}}),
        'get_profile' => (200, {'js': {'status': 0}}),
        'get_genres' => (200, {'js': [
            {'id': '*', 'title': 'All'}, {'id': '5', 'title': 'PORTUGAL'}, {'id': '6', 'title': 'UK'},
          ]}),
        'get_all_channels' => todos
            ? (200, {'js': {'data': [
                {'id': '1', 'name': 'PT: RTP 1', 'tv_genre_id': '5', 'cmd': 'ffrt http://localhost/ch/1'},
                {'id': '2', 'name': 'BBC', 'tv_genre_id': '6', 'cmd': 'ffrt http://localhost/ch/2'},
              ]}})
            : (200, {'js': {'data': []}}),
        'get_ordered_list' => q['p'] == '1'
            ? (200, {'js': {'total_items': 3, 'max_page_items': 2, 'data': [
                {'id': '1', 'name': 'A', 'tv_genre_id': '5'}, {'id': '2', 'name': 'B', 'tv_genre_id': '5'}]}})
            : (200, {'js': {'total_items': 3, 'max_page_items': 2, 'data': [
                {'id': '3', 'name': 'C', 'tv_genre_id': '99'}]}}),
        'create_link' => (200, {'js': {'cmd': linkVazio
            ? 'ffrt http://srv/play/live.php?mac=$mac&stream=&extension=ts'
            : 'ffrt http://srv/play/1.ts'}}),
        _ => (404, ''),
      };
    }

    test('abre com o 2.º endpoint, agrupa por género e pede o link', () async {
      srv.responder = portal;
      final c = Conta('x', Tipo.stalker, '${srv.url}/stalker_portal/c/', mac: mac);
      final s = Stalker();
      final conteudo = await s.abrir(c);
      expect(conteudo.grupos, ['PORTUGAL', 'UK']);
      expect(conteudo.doGrupo('PORTUGAL').single.nome, 'PT: RTP 1');
      final f = await s.fonte(c, conteudo.canais.first);
      expect(f.url, 'http://srv/play/1.ts');
      expect(f.headers['Cookie'], contains('mac=$mac'));
      expect(srv.pedidos.where((p) => p.uri.queryParameters['action'] == 'handshake'), hasLength(2));
    });

    test('sem get_all_channels lê página a página', () async {
      srv.responder = (p) => portal(p, todos: false);
      final c = Conta('x', Tipo.stalker, '${srv.url}/stalker_portal/c/', mac: mac);
      final conteudo = await Stalker().abrir(c);
      expect(conteudo.canais.map((c) => c.nome), ['A', 'B', 'C']);
      expect(conteudo.grupos, ['PORTUGAL', 'Sem grupo']);
    });

    test('stream vazio no create_link é preenchido', () async {
      srv.responder = (p) => portal(p, linkVazio: true);
      final c = Conta('x', Tipo.stalker, '${srv.url}/stalker_portal/c/', mac: mac);
      final s = Stalker();
      final conteudo = await s.abrir(c);
      expect((await s.fonte(c, conteudo.canais.first)).url, contains('stream=1&extension=ts'));
    });

    test('portal inexistente dá erro legível', () async {
      final c = Conta('x', Tipo.stalker, '${srv.url}/c/', mac: mac);
      expect(() => Stalker().abrir(c), throwsA(isA<ErroLista>()));
    });

    test('preencherStream e limparCmd', () {
      const canal = Canal(id: '7', nome: 'x', grupo: 'g', cmd: 'ffrt http://h/ch?stream=99');
      expect(preencherStream('http://h/p?stream=&x=1', canal), 'http://h/p?stream=99&x=1');
      expect(preencherStream('http://h/p?stream=5', canal), 'http://h/p?stream=5');
      expect(limparCmd('ffmpeg http://a'), 'http://a');
    });
  });

  group('M3U', () {
    test('por URL e cancelamento', () async {
      srv.responder = (_) => (200, '#EXTM3U\n#EXTINF:-1 group-title="G",Um\nhttp://s/1.ts\n');
      final c = Conta('x', Tipo.m3u, '${srv.url}/lista.m3u');
      final conteudo = await Protocolo.para(c).abrir(c);
      expect(conteudo.canais.single.nome, 'Um');
      final f = await Protocolo.para(c).fonte(c, conteudo.canais.single);
      expect((f.url, f.headers['User-Agent']), ('http://s/1.ts', uaVlc));
      final can = Cancelamento()..cancelar();
      expect(() => Protocolo.para(c).abrir(c, cancelamento: can), throwsA(isA<Cancelado>()));
    });

    test('um endereço que não é M3U', () async {
      srv.responder = (_) => (200, '<html>login</html>');
      final c = Conta('x', Tipo.m3u, '${srv.url}/x');
      expect(() => Protocolo.para(c).abrir(c), throwsA(isA<ErroLista>()));
    });
  });
}
