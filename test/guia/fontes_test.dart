import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/guia/fontes.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/protocolos/stalker.dart';
import 'package:player_iptv/rede/http.dart';

import '../apoio/servidor_falso.dart';
import 'xmltv_test.dart' show agora, programa;

void main() {
  late ServidorFalso srv;
  setUp(() async {
    srv = ServidorFalso((_) => (404, 'nada'));
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  Conta xtream() => Conta('x', Tipo.xtream, srv.url, utilizador: 'u', password: 'p');
  const rtp = Canal(id: '10', nome: 'RTP 1', grupo: 'PT', epg: 'rtp1.pt');

  group('Xtream', () {
    test('xmltv.php: lido num isolate, só a janela dos canais da lista, com o ETag', () async {
      srv.responder = (p) {
        if (p.uri.path != '/xmltv.php') return (404, '');
        p.response.headers.set('etag', '"v1"');
        return (200, '<tv>${programa('rtp1.pt', agora - 60, agora + 600, 'Telejornal')}'
            '${programa('outro', agora, agora + 60, 'Fora')}</tv>');
      };
      final r = await GuiaXtream(agora: () => agora).todos(xtream(), [rtp]);
      expect(r.porCanal.keys, ['10']);
      expect(r.porCanal['10']!.single.titulo, 'Telejornal');
      expect(r.etag, '"v1"');
      expect(srv.pedidos.single.uri.queryParameters, {'username': 'u', 'password': 'p'});
    });

    test('o servidor diz que não mudou (304): não se lê nada', () async {
      srv.responder = (p) => p.headers.value('if-none-match') == '"v1"' ? (304, '') : (200, '<tv></tv>');
      final anterior = GuiaLista({}, criado: DateTime(2026), etag: '"v1"');
      final r = await GuiaXtream(agora: () => agora).todos(xtream(), [rtp], anterior: anterior);
      expect(r.naoMudou, isTrue);
    });

    test('um erro HTTP do xmltv.php chega como ErroHttp', () async {
      srv.responder = (_) => (403, 'proibido');
      expect(GuiaXtream(agora: () => agora).todos(xtream(), [rtp]), throwsA(isA<ErroHttp>()));
    });

    test('cancelar mata a leitura', () async {
      srv.responder = (_) => (200, '<tv>');
      final c = Cancelamento()..cancelar();
      expect(GuiaXtream(agora: () => agora).todos(xtream(), [rtp], cancelamento: c), throwsA(isA<Cancelado>()));
    });

    test('get_short_epg: os títulos em base64 e só o que ainda não acabou', () async {
      String b64(String t) => base64.encode(utf8.encode(t));
      srv.responder = (p) => (200, {
            'epg_listings': [
              {'title': b64('Já foi'), 'description': '', 'start_timestamp': '${agora - 7200}',
                  'stop_timestamp': '${agora - 3600}'},
              {'title': b64('Notícias às 13'), 'description': b64('Resumo'), 'start_timestamp': '${agora - 60}',
                  'stop_timestamp': '${agora + 600}'},
            ],
          });
      final ps = await GuiaXtream(agora: () => agora).doCanal(xtream(), rtp);
      expect(ps.map((p) => (p.titulo, p.descricao)), [('Notícias às 13', 'Resumo')]);
      expect(srv.pedidos.single.uri.queryParameters['action'], 'get_short_epg');
      expect(srv.pedidos.single.uri.queryParameters['stream_id'], '10');
    });
  });

  group('portal MAC', () {
    Conta mac() => Conta('m', Tipo.stalker, '${srv.url}/c/', mac: '00:1A:79:00:00:01');
    Resposta portal(HttpRequest p, Object? epg) {
      final a = p.uri.queryParameters['action'];
      if (a == 'handshake') return (200, {'js': {'token': 't'}});
      if (a == 'get_profile') return (200, {'js': {}});
      return (200, {'js': epg});
    }

    test('get_epg_info: o guia de todos os canais (por id), sem os que não são da lista', () async {
      srv.responder = (p) => portal(p, {
            'data': {
              '10': [
                {'name': 'Telejornal', 'descr': 'Notícias', 'start_timestamp': agora - 60, 'stop_timestamp': agora + 600},
                {'name': 'Novela', 'start_timestamp': agora + 600, 'stop_timestamp': agora + 3600},
              ],
              '99': [
                {'name': 'Outro', 'start_timestamp': agora, 'stop_timestamp': agora + 60},
              ],
            },
          });
      final r = await GuiaStalker(agora: () => agora, stalker: Stalker()).todos(mac(), [rtp]);
      expect(r.porCanal.keys, ['10']);
      expect(r.porCanal['10']!.map((p) => p.titulo), ['Telejornal', 'Novela']);
      expect(r.porCanal['10']!.first.descricao, 'Notícias');
    });

    test('get_short_epg de um canal', () async {
      srv.responder = (p) => portal(p, [
            {'name': 'Telejornal', 'start_timestamp': '${agora - 60}', 'stop_timestamp': '${agora + 600}'},
          ]);
      final ps = await GuiaStalker(agora: () => agora, stalker: Stalker()).doCanal(mac(), rtp);
      expect(ps.single.titulo, 'Telejornal');
      expect(srv.pedidos.last.uri.queryParameters['ch_id'], '10');
    });
  });

  test('deBase64: texto que não é base64 fica como está', () {
    expect(deBase64('Telejornal'), 'Telejornal');
    expect(deBase64(base64.encode(utf8.encode('Notícias'))), 'Notícias');
  });
}
