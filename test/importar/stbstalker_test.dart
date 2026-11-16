import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/importar/stbstalker.dart';

import '../apoio/servidor_falso.dart';

const _post = '''<div><p>http://portal.exemplo:8080/c/</p>
<p>00:1a:79:aa:bb:cc<br/>00:1A:79:11:22:33</p>
<p>https://stbstalker.alaaeldinee.com/x</p></div>''';

void main() {
  late ServidorFalso srv;
  final rotas = <String, String>{};

  setUp(() async {
    rotas
      ..clear()
      ..addAll({
        '/': '<a href="/2026/11/stb-14-11-2026.html">a</a><a href="/2026/11/stb-10-11-2026.html">b</a>',
        '/2026/11/stb-14-11-2026.html': _post,
        '/2026/11/stb-10-11-2026.html': '<p>http://outro.exemplo/c/ 00:1A:79:00:00:09</p>',
      });
    srv = ServidorFalso((p) {
      final k = p.uri.hasQuery ? '${p.uri.path}?${p.uri.query}' : p.uri.path;
      final c = rotas[k];
      return c == null ? (404, 'nada') : (200, c);
    });
    await srv.iniciar();
  });
  tearDown(() => srv.parar());

  test('extrairPares: MAC em maiúsculas, associado ao portal acima, ignora o blog', () {
    final r = extrairPares('http://portal.exemplo:8080/c/\n00:1a:79:aa:bb:cc 00:1A:79:11:22:33\n'
        'https://stbstalker.alaaeldinee.com/x\n00:1A:79:00:00:01');
    expect(r, [
      'http://portal.exemplo:8080/c/ 00:1A:79:AA:BB:CC',
      'http://portal.exemplo:8080/c/ 00:1A:79:11:22:33',
      'http://portal.exemplo:8080/c/ 00:1A:79:00:00:01',
    ]);
  });

  test('extrairPares: a mesma lista escrita de outra forma entra uma vez', () {
    expect(extrairPares('http://x/c/ 00:1A:79:00:00:01\nhttp://x 00:1A:79:00:00:01'),
        ['http://x/c/ 00:1A:79:00:00:01']);
  });

  test('dataDoPost lê a data do slug', () {
    expect(dataDoPost('https://a/2026/11/smart-11-11-2026.html'), DateTime(2026, 11, 11));
    expect(dataDoPost('https://a/2026/11/sem-data.html'), isNull);
    expect(dataDoPost('https://a/2026/11/x-31-02-2026.html'), isNull);
  });

  test('importarEntre junta os posts do intervalo', () async {
    var r = await importarEntre(DateTime(2026, 11, 1), DateTime(2026, 11, 30), base: '${srv.url}/');
    expect(r.total, 3);
    expect([for (final p in r.posts) p.data], [DateTime(2026, 11, 14), DateTime(2026, 11, 10)]);
    r = await importarEntre(DateTime(2026, 11, 14), DateTime(2026, 11, 14), base: '${srv.url}/');
    expect(r.linhas, ['http://portal.exemplo:8080/c/ 00:1A:79:AA:BB:CC',
      'http://portal.exemplo:8080/c/ 00:1A:79:11:22:33']);
    r = await importarEntre(DateTime(2026, 11, 1), DateTime(2026, 11, 12), base: '${srv.url}/');
    expect(r.linhas, ['http://outro.exemplo/c/ 00:1A:79:00:00:09']);
  });

  test('sem posts no intervalo devolve o erro com as datas', () async {
    var r = await importarEntre(DateTime(2026, 11, 11), DateTime(2026, 11, 13), base: '${srv.url}/');
    expect(r.erro, 'Nenhum post publicado entre 11/11/2026 e 13/11/2026.');
    r = await importarEntre(DateTime(2026, 11, 11), DateTime(2026, 11, 11), base: '${srv.url}/');
    expect(r.erro, 'Nenhum post publicado em 11/11/2026.');
  });

  test('fim antes do início lança', () {
    expect(() => importarEntre(DateTime(2026, 11, 14), DateTime(2026, 11, 1), base: '${srv.url}/'),
        throwsArgumentError);
  });

  test('postsEntre recua pelas páginas até passar a data de início', () async {
    rotas['/'] = '<a href="/2026/11/stb-14-11-2026.html">a</a>'
        '<a href="/?updated-max=2026-11-10&amp;max-results=2">mais</a>';
    rotas['/?updated-max=2026-11-10&max-results=2'] = '<a href="/2026/11/stb-05-11-2026.html">c</a>'
        '<a href="/2026/10/stb-28-10-2026.html">d</a><a href="/?updated-max=2026-10-01">mais</a>';
    final r = await postsEntre(DateTime(2026, 11, 1), DateTime(2026, 11, 30), base: '${srv.url}/');
    expect([for (final p in r) p.data], [DateTime(2026, 11, 14), DateTime(2026, 11, 5)]);
    expect(srv.pedidos.length, 2); // parou ao passar o início
  });
}
