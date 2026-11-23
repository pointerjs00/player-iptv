import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/importar/telegram.dart';
import 'package:player_iptv/modelo/conta.dart';

import '../apoio/servidor_falso.dart';

/// Uma mensagem como a página `t.me/s/<canal>` a mostra (ao meio-dia UTC: o dia local não muda
/// em nenhum fuso razoável).
String _msg(int id, String dia, String interno) => '''
<div class="tgme_widget_message_wrap js-widget_message_wrap">
  <div class="tgme_widget_message text" data-post="michelstv4/$id" data-view="1">
    <div class="tgme_widget_message_text js-message_text" dir="auto">$interno</div>
    <div class="tgme_widget_message_footer"><span class="tgme_widget_message_meta">
      <a class="tgme_widget_message_date" href="https://t.me/michelstv4/$id">
        <time datetime="${dia}T12:00:00+00:00" class="time">12:00</time></a></span></div>
  </div>
</div>''';

/// Um link (como o Telegram o mostra: <a href>).
String _link(String url) =>
    '<a href="${url.replaceAll('&', '&amp;')}" target="_blank" rel="noopener">$url</a>';

void main() {
  group('canalDeTexto', () {
    test('aceita @nome, t.me/nome, t.me/s/nome, link e nome simples', () {
      for (final e in ['michelstv4', '@michelstv4', 't.me/michelstv4', 'https://t.me/s/michelstv4',
        'http://telegram.me/michelstv4', '  @michelstv4 ']) {
        expect(canalDeTexto(e), 'michelstv4', reason: e);
      }
    });
    test('recusa o que não parece um canal', () {
      for (final e in ['', 'ab', 'tem espaço', 'http://portal.com/c/', '@@x']) {
        expect(canalDeTexto(e), isNull, reason: e);
      }
    });
  });

  test('contasDaMensagem: Xtream, portal+MAC, ignora links t.me e repetidos', () {
    final contas = contasDaMensagem('Portal : http://exchange.jinbox.nl/c/\n'
        'MAC Addr: 00:1A:79:B9:E7:91\n'
        'http://line.x.org/get.php?username=u&password=p&type=m3u\n'
        'http://line.x.org/get.php?username=u&password=p\n' // a mesma conta Xtream
        'https://t.me/outrocanal/42'); // link do Telegram: ignora-se
    expect(contas.map((c) => (c.tipo, c.endereco, c.mac, c.utilizador)), [
      (Tipo.stalker, 'http://exchange.jinbox.nl/c/', '00:1A:79:B9:E7:91', ''),
      (Tipo.xtream, 'http://line.x.org', '', 'u'),
    ]);
  });

  group('importarTelegram', () {
    late ServidorFalso srv;
    final rotas = <String, String>{};

    setUp(() async {
      rotas.clear();
      srv = ServidorFalso((p) {
        final k = p.uri.hasQuery ? '${p.uri.path}?${p.uri.query}' : p.uri.path;
        final c = rotas[k];
        return c == null ? (404, 'nada') : (200, c);
      });
      await srv.iniciar();
    });
    tearDown(() => srv.parar());

    String base() => '${srv.url}/s/';

    test('junta as listas das mensagens no intervalo', () async {
      rotas['/s/michelstv4'] = _msg(14992, '2026-11-22', _link('http://a.tv/get.php?username=u1&password=p1&type=m3u')) +
          _msg(14991, '2026-11-22', 'Portal : http://exchange.jinbox.nl/c/<br>MAC Addr: 00:1A:79:B9:E7:91') +
          _msg(14990, '2026-11-20', _link('http://b.tv/get.php?username=u2&password=p2&type=m3u'));
      final r = await importarTelegram('michelstv4', DateTime(2026, 11, 22), DateTime(2026, 11, 22), base: base());
      expect(r.erro, isNull);
      expect(r.mensagens, 2);
      expect(r.contas.map((c) => c.endereco), ['http://a.tv', 'http://exchange.jinbox.nl/c/']);
    });

    test('recua com ?before até passar a data de início e não repete listas', () async {
      rotas['/s/michelstv4'] = _msg(102, '2026-11-22', _link('http://a.tv/get.php?username=u&password=p')) +
          _msg(101, '2026-11-21', _link('http://a.tv/get.php?username=u&password=p')); // repetida
      rotas['/s/michelstv4?before=101'] = _msg(100, '2026-11-20', _link('http://c.tv/get.php?username=u&password=p')) +
          _msg(99, '2026-11-18', _link('http://d.tv/get.php?username=u&password=p'));
      final r = await importarTelegram('michelstv4', DateTime(2026, 11, 20), DateTime(2026, 11, 22), base: base());
      expect(r.contas.map((c) => c.endereco), ['http://a.tv', 'http://c.tv']);
      expect(srv.pedidos.length, 2); // parou ao chegar a 18/11, antes do início
    });

    test('sem mensagens no intervalo devolve o erro com as datas', () async {
      rotas['/s/michelstv4'] = _msg(5, '2026-11-10', _link('http://a.tv/get.php?username=u&password=p'));
      var r = await importarTelegram('michelstv4', DateTime(2026, 11, 20), DateTime(2026, 11, 22), base: base());
      expect(r.erro, 'Nenhuma mensagem publicada entre 20/11/2026 e 22/11/2026.');
      r = await importarTelegram('michelstv4', DateTime(2026, 11, 20), DateTime(2026, 11, 20), base: base());
      expect(r.erro, 'Nenhuma mensagem publicada em 20/11/2026.');
    });

    test('fim antes do início lança', () {
      expect(() => importarTelegram('michelstv4', DateTime(2026, 11, 22), DateTime(2026, 11, 1), base: base()),
          throwsArgumentError);
    });

    test('mensagem sem texto (anexo) e link t.me não entram', () async {
      const anexo = '<div class="tgme_widget_message_wrap"><div class="tgme_widget_message" data-post="michelstv4/9" '
          'data-view="1"><div class="tgme_widget_message_document"><div class="tgme_widget_message_document_title">lista.m3u</div></div>'
          '<div class="tgme_widget_message_footer"><time datetime="2026-11-22T12:00:00+00:00"></time></div></div></div>';
      rotas['/s/michelstv4'] = _msg(10, '2026-11-22', _link('http://a.tv/get.php?username=u&password=p')) +
          anexo +
          _msg(8, '2026-11-22', _link('https://t.me/outro/1'));
      final r = await importarTelegram('michelstv4', DateTime(2026, 11, 22), DateTime(2026, 11, 22), base: base());
      expect(r.mensagens, 3);
      expect(r.contas.map((c) => c.endereco), ['http://a.tv']);
    });
  });
}
