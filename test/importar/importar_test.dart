import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/importar/m3u.dart';
import 'package:player_iptv/modelo/conta.dart';

void main() {
  group('.ini', () {
    test('o exemplo do Stalker Portal Player (CRLF e LF)', () {
      for (final fim in ['\r\n', '\n']) {
        final c = lerIni('[DNS]${fim}Address=http://nxtbox.uk${fim}Mac=00:1a:79:00:00:01$fim',
            '003NXTBOX 161027.ini')!;
        expect((c.nome, c.tipo, c.endereco, c.mac),
            ('003NXTBOX 161027', Tipo.stalker, 'http://nxtbox.uk', '00:1A:79:00:00:01'));
      }
    });
    test('sem Mac não é lista', () {
      expect(lerIni('[DNS]\nAddress=http://x', 'a.ini'), isNull);
      expect(() => importarFicheiro('a.ini', '[DNS]'), throwsA(isA<ErroImportacao>()));
    });
  });

  test('Accounts.json com campos em falta e lixo', () {
    final t = jsonEncode([
      {'Name': 'A', 'Address': 'http://x/c/', 'Mac': '00:1a:79:00:00:01'},
      {'Name': 'B', 'Address': 'http://y:8080', 'Username': 'u', 'Password': 'p'},
      {'Name': 'sem endereço'},
      5,
    ]);
    final cs = lerAccountsJson('\uFEFF$t');
    expect(cs.map((c) => c.tipo), [Tipo.stalker, Tipo.xtream]);
    expect(() => lerAccountsJson('{nao'), throwsA(isA<ErroImportacao>()));
  });

  test('.txt com linhas misturadas', () {
    final r = importarFicheiro('listas.txt', '''
http://a.com/c/ 00:1A:79:00:00:01
lixo qualquer
http://b.com:8080/get.php?username=u&password=p&type=m3u_plus
http://c.com/lista.m3u
''');
    expect(r.map((i) => i.conta.tipo), [Tipo.stalker, Tipo.xtream, Tipo.m3u]);
    expect(() => importarFicheiro('vazio.txt', 'nada aqui'), throwsA(isA<ErroImportacao>()));
  });

  test('histórico do verificador: a entrada mais recente ganha', () {
    Map r(String estado, String validade) => {
          'nome': 'x', 'estado': estado, 'motivo': 'm', 'validade': validade,
          'conta': {'Name': 'A', 'Address': 'http://x/c/', 'Mac': '00:1A:79:00:00:01'},
        };
    final t = jsonEncode([
      {'id': '2', 'data_hora': '2026-11-15T10:00:00', 'resultados': [r('funciona', '2027-01-01')]},
      {'id': '1', 'data_hora': '2026-11-14T10:00:00', 'resultados': [r('nao_funciona', '')]},
      {'id': '3', 'data_hora': '2026-11-16T10:00:00', 'resultados': [r('', ''), 'lixo']},
      'lixo',
    ]);
    final imp = importarFicheiro('historico.json', t);
    expect(imp, hasLength(1));
    expect(imp.single.ultima!.estado, 'funciona');
    expect(imp.single.ultima!.validade, '2027-01-01');
    expect(imp.single.ultima!.data, DateTime(2026, 11, 15, 10));
  });

  group('M3U', () {
    test('grupos, logos, opções e nomes com vírgulas', () {
      final c = lerM3u('''#EXTM3U
#EXTINF:-1 tvg-logo="http://l/1.png" group-title="Portugal",PT: RTP 1 HD
http://s/1.ts
#EXTINF:-1 tvg-name="X, Y" group-title="Desporto, PT",Sport TV 1
#EXTVLCOPT:http-user-agent=Meu UA
#EXTVLCOPT:http-referrer=http://ref/
http://s/2.ts
#EXTINF:-1,Sem grupo nenhum
http://s/3.ts
#EXTINF:-1 group-title="Portugal",RTP 2
http://s/4.ts
''');
      expect(c.grupos, ['Portugal', 'Desporto, PT', semGrupo]);
      expect(c.canais.map((x) => x.nome), ['PT: RTP 1 HD', 'Sport TV 1', 'Sem grupo nenhum', 'RTP 2']);
      expect(c.canais[0].logo, 'http://l/1.png');
      expect((c.canais[1].userAgent, c.canais[1].referer), ('Meu UA', 'http://ref/'));
      expect(c.doGrupo('Portugal'), hasLength(2));
      expect(c.contagens()['Portugal'], 2);
    });

    test('100 000 canais em menos de 2 s', () {
      final b = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 100000; i++) {
        b.write('#EXTINF:-1 group-title="G${i % 50}",Canal $i\nhttp://s/$i.ts\n');
      }
      final t0 = DateTime.now();
      final c = lerM3u(b.toString());
      expect(c.canais, hasLength(100000));
      expect(DateTime.now().difference(t0).inMilliseconds, lessThan(2000));
    });

    test('ficheiro M3U importa-se como lista local', () {
      final imp = importarFicheiro('minha.m3u', '#EXTM3U\n', caminho: r'C:\listas\minha.m3u');
      expect(imp.single.conta.tipo, Tipo.m3u);
      expect(imp.single.conta.endereco, startsWith('file:///'));
      expect(imp.single.conta.nome, 'minha');
    });
  });
}
