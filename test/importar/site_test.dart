import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/importar/site.dart';
import 'package:player_iptv/modelo/conta.dart';

import '../apoio/servidor_falso.dart';

void main() {
  late ServidorFalso srv;
  setUp(() async {
    srv = ServidorFalso((_) => (404, 'nada'));
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  final hoje = DateTime.now();
  final ontem = hoje.subtract(const Duration(days: 1));
  String iso(DateTime d) => d.toUtc().toIso8601String();

  const post1 = '<p>Portal: http://portal.um.tv/c/<br>00:1A:79:00:00:01</p>'
      '<p><a href="http://xt.tv:8080/get.php?username=u&amp;password=p&amp;type=m3u_plus">Xtream</a></p>';
  const post2 = '<div>Lista: http://listas.tv/canais.m3u8 e mais nada</div>'
      '<a href="https://blog.exemplo/2026/11/outro-post.html">outro post</a>'
      '<img src="https://blog.exemplo/imagem.png">';

  group('Blogger (feed com datas)', () {
    test('os posts do período: portal + MAC, Xtream e M3U; os links do blog ficam de fora', () async {
      srv.responder = (p) {
        if (p.uri.path != '/feeds/posts/default') return (404, '');
        expect(p.uri.queryParameters['alt'], 'json');
        return (200, {
          'feed': {
            'entry': [
              {'published': {r'$t': iso(hoje)}, 'content': {r'$t': post1}},
              {'published': {r'$t': iso(ontem)}, 'content': {r'$t': post2}},
            ],
          },
        });
      };
      final r = await importarSite('${srv.url}/', ontem, hoje);
      expect(r.tipo, TipoSite.blogger);
      expect(r.lidas, 2);
      expect(r.erro, isNull);
      expect(r.contas.map((c) => (c.tipo, c.endereco)).toSet(), {
        (Tipo.stalker, 'http://portal.um.tv/c/'),
        (Tipo.xtream, 'http://xt.tv:8080'),
        (Tipo.m3u, 'http://listas.tv/canais.m3u8'),
      });
    });

    test('um post fora das datas (o servidor ignorou o filtro) não conta', () async {
      srv.responder = (p) => p.uri.path == '/feeds/posts/default'
          ? (200, {
              'feed': {
                'entry': [
                  {'published': {r'$t': iso(hoje.subtract(const Duration(days: 30)))}, 'content': {r'$t': post1}},
                ],
              },
            })
          : (404, '');
      final r = await importarSite('${srv.url}/', hoje, hoje);
      expect(r.contas, isEmpty);
      expect(r.erro, startsWith('Nenhum post publicado'));
    });
  });

  test('WordPress (sem Blogger): os posts pela API, entre as datas', () async {
    srv.responder = (p) {
      if (p.uri.path != '/wp-json/wp/v2/posts') return (404, '');
      expect(p.uri.queryParameters['per_page'], '50');
      return (200, [
        {'date': hoje.toIso8601String(), 'content': {'rendered': post1}},
      ]);
    };
    final r = await importarSite('${srv.url}/', hoje, hoje);
    expect(r.tipo, TipoSite.wordpress);
    expect(r.contas, hasLength(2));
  });

  test('outro site: lê-se só a página inicial', () async {
    srv.responder = (p) => p.uri.path == '/' ? (200, '<html><body>$post2</body></html>') : (404, '');
    final r = await importarSite('${srv.url}/', hoje, hoje);
    expect(r.tipo, TipoSite.pagina);
    expect(r.contas.single.endereco, 'http://listas.tv/canais.m3u8');
  });

  test('o endereço de um post: lê-se só esse, sem procurar feeds', () async {
    srv.responder = (p) => p.uri.path == '/2026/11/listas.html' ? (200, post1) : (500, 'não devia pedir');
    final r = await importarSite('${srv.url}/2026/11/listas.html', hoje, hoje);
    expect(r.tipo, TipoSite.pagina);
    expect(r.contas, hasLength(2));
    expect(srv.pedidos.map((p) => p.uri.path), ['/2026/11/listas.html']);
  });

  test('uma página sem listas diz isso mesmo', () async {
    srv.responder = (p) => (200, '<p>Olá</p><a href="https://site.pt/sobre">sobre</a>');
    final r = await importarSite('${srv.url}/sobre.html', hoje, hoje);
    expect(r.erro, 'A página não tem listas (Xtream, M3U ou portal MAC) no texto.');
  });

  test('um site que não responde dá o erro de rede', () async {
    final fechado = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final porta = fechado.port;
    await fechado.close();
    expect(importarSite('http://127.0.0.1:$porta/pagina.html', hoje, hoje), throwsA(isA<SocketException>()));
  });

  group('siteDeTexto', () {
    test('junta https:// e a barra; recusa o que não é um site', () {
      expect(siteDeTexto('blog.exemplo.pt'), 'https://blog.exemplo.pt/');
      expect(siteDeTexto(' http://x.pt/post.html '), 'http://x.pt/post.html');
      expect(siteDeTexto('não é um site'), isNull);
      expect(siteDeTexto(''), isNull);
    });
  });
}
