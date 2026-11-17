import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/verificador.dart';

import '../apoio/servidor_falso.dart';
import 'verificar_test.dart' show ts;

const mac = '00:1A:79:00:00:01';

Future<ResultadoVerificacao?> _semDns(String _) async => null;

/// C1: casos em que o Python (motor/xtream.py, m3u.py, stalker.py) dá INC e não "Não funciona".
void main() {
  late ServidorFalso srv;
  setUp(() async {
    srv = ServidorFalso((_) => (404, ''));
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  final v = Verificador(dns: _semDns, espera: Duration.zero, pausaReteste: Duration.zero);
  Future<ResultadoVerificacao> uma(Conta c) => v.verificarUmaVez(c, const ['rtp1']);

  group('C1: Xtream', () {
    Conta conta() => Conta('x', Tipo.xtream, srv.url, utilizador: 'u', password: 'p');
    Resposta painel(HttpRequest p,
        {int api = 200, int categorias = 200, int canais = 200, List? streams, Map? extra, int stream = 200}) {
      if (p.uri.path == '/player_api.php') {
        return switch (p.uri.queryParameters['action']) {
          null => api == 200
              ? (200, {'user_info': {'auth': '1', 'status': 'Active', 'exp_date': '0', ...?extra}})
              : (api, ''),
          'get_live_categories' =>
            categorias == 200 ? (200, [{'category_id': '1', 'category_name': 'PT'}]) : (categorias, ''),
          'get_live_streams' => canais == 200
              ? (200, streams ?? [{'stream_id': 1, 'name': 'PT: RTP 1', 'category_id': '1'}])
              : (canais, ''),
          _ => (404, ''),
        };
      }
      if (p.uri.path.startsWith('/live/')) return (stream, stream == 200 ? ts() : '');
      return (404, '');
    }

    for (final status in [401, 403, 404]) {
      test('C1: player_api.php $status é INC (test_http_401_403_inconclusivo / test_http_na_api_inconclusivo)',
          () async {
        srv.responder = (p) => painel(p, api: status);
        final r = await uma(conta());
        expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'a API respondeu $status'));
      });
    }

    test('C1: get_live_categories 404 não interessa à verificação', () async {
      srv.responder = (p) => painel(p, categorias: 404);
      expect((await uma(conta())).estado, EstadoV.funciona);
    });

    test('C1: get_live_streams com erro HTTP é INC (test_http_na_lista_de_canais_inconclusivo)', () async {
      srv.responder = (p) => painel(p, canais: 403);
      final r = await uma(conta());
      expect(r.estado, EstadoV.inconclusivo);
      expect(r.motivo, startsWith('não foi possível listar os canais'));
    });

    test('C1: get_live_streams vazio é INC "conta sem canais"', () async {
      srv.responder = (p) => painel(p, streams: const []);
      final r = await uma(conta());
      expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'conta sem canais'));
    });

    test('C1: limite de ligações atingido e stream recusado explica (test_limite_de_ligacoes_..._explica)',
        () async {
      srv.responder = (p) => painel(p, extra: {'active_cons': '1', 'max_connections': '1'}, stream: 404);
      final r = await uma(conta());
      expect(r.estado, EstadoV.inconclusivo);
      expect(r.motivo, startsWith('limite de ligações atingido (1/1)'));
    });

    test('C1: limite de ligações atingido mas o stream abre: funciona', () async {
      srv.responder = (p) => painel(p, extra: {'active_cons': '2', 'max_connections': '1'});
      expect((await uma(conta())).estado, EstadoV.funciona);
    });
  });

  group('C1: M3U', () {
    Conta conta() => Conta('x', Tipo.m3u, '${srv.url}/lista.m3u');
    for (final status in [401, 403]) {
      test('C1: lista $status é INC (R12, test_lista_403_inconclusivo)', () async {
        srv.responder = (_) => (status, '');
        final r = await uma(conta());
        expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'servidor recusou o acesso à lista ($status)'));
      });
    }

    test('C1: HTML ou captive portal é INC (R13, test_lista_html_inconclusivo)', () async {
      srv.responder = (_) => (200, '<html><body>login #EXTINF</body></html>');
      final r = await uma(conta());
      expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'o endereço não devolveu uma lista M3U'));
    });

    test('C1: lista com BOM e espaços antes de #EXTM3U continua a funcionar', () async {
      srv.responder = (p) => p.uri.path == '/lista.m3u'
          ? (200, '﻿ \n#EXTM3U\n#EXTINF:-1,PT: RTP 1\n${srv.url}/s.ts\n')
          : (200, ts());
      expect((await uma(conta())).estado, EstadoV.funciona);
    });

    test('C1: #EXTM3U sem entradas continua NF (test_extm3u_sem_entradas_nao_funciona)', () async {
      srv.responder = (_) => (200, '#EXTM3U\n');
      expect((await uma(conta())).estado, EstadoV.naoFunciona);
    });
  });

  group('C1: Stalker', () {
    Conta conta() => Conta('x', Tipo.stalker, '${srv.url}/c/', mac: mac);
    Resposta portal(HttpRequest p, Resposta Function(Map<String, String> q) canais) {
      final q = p.uri.queryParameters;
      return switch (q['action']) {
        'handshake' => (200, {'js': {'token': 'T'}}),
        'get_profile' => (200, {'js': {'status': 0}}),
        'get_main_info' => (200, {'js': {}}),
        'get_genres' => (200, {'js': []}),
        'get_all_channels' || 'get_ordered_list' => canais(q),
        _ => (404, ''),
      };
    }

    Map pagina(List<String> nomes, {int total = 6, int porPagina = 2}) => {
          'js': {
            'total_items': total,
            'max_page_items': porPagina,
            'data': [for (final n in nomes) {'id': n, 'name': n, 'cmd': 'ffrt http://localhost/$n'}],
          }
        };

    test('C1: get_ordered_list página 2 com 403 é INC (lista incompleta)', () async {
      srv.responder = (p) => portal(p, (q) => switch ((q['action'], q['p'])) {
            ('get_all_channels', _) => (200, {'js': {'data': []}}),
            (_, '1') => (200, pagina(['A', 'B'])),
            _ => (403, ''),
          });
      final r = await uma(conta());
      expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'RTP 1 não encontrada (lista de canais incompleta)'));
    });

    test('C1: página vazia antes do total é INC (test_pagina_vazia_antes_do_total_e_inconclusivo)', () async {
      srv.responder = (p) => portal(p, (q) => switch ((q['action'], q['p'])) {
            ('get_all_channels', _) => (200, {'js': {'data': []}}),
            (_, '1') => (200, pagina(['A', 'B'])),
            _ => (200, pagina([])),
          });
      expect((await uma(conta())).estado, EstadoV.inconclusivo);
    });

    test('C1: página que não é um mapa é INC', () async {
      srv.responder = (p) => portal(p, (q) => switch ((q['action'], q['p'])) {
            ('get_all_channels', _) => (200, {'js': {'data': []}}),
            (_, '1') => (200, pagina(['A', 'B'])),
            _ => (200, 'lixo'),
          });
      expect((await uma(conta())).estado, EstadoV.inconclusivo);
    });

    test('C1: get_all_channels com total_items maior do que os dados é INC', () async {
      srv.responder = (p) => portal(p, (q) => switch (q['action']) {
            'get_all_channels' => (200, pagina(['A', 'B'], total: 500)),
            _ => (403, ''),
          });
      final r = await uma(conta());
      expect((r.estado, r.motivo), (EstadoV.inconclusivo, 'RTP 1 não encontrada (lista de canais incompleta)'));
    });

    test('C1: paginação completa sem RTP 1 continua NF (test_paginacao_completa_sem_rtp1_nao_funciona)',
        () async {
      srv.responder = (p) => portal(p, (q) => switch ((q['action'], q['p'])) {
            ('get_all_channels', _) => (200, {'js': {'data': []}}),
            (_, '1') => (200, pagina(['A', 'B'], total: 3)),
            (_, '2') => (200, pagina(['C'], total: 3)),
            _ => (200, pagina([], total: 3)),
          });
      final r = await uma(conta());
      expect((r.estado, r.motivo), (EstadoV.naoFunciona, 'RTP 1 não existe na conta'));
    });

    test('C1: erro HTTP logo na 1.ª página é INC "não foi possível listar os canais"', () async {
      srv.responder = (p) => portal(p, (q) => (403, ''));
      final r = await uma(conta());
      expect(r.estado, EstadoV.inconclusivo);
      expect(r.motivo, startsWith('não foi possível listar os canais'));
    });
  });
}
