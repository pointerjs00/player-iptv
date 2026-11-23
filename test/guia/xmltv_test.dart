import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/guia/fontes.dart';
import 'package:player_iptv/guia/programa.dart';
import 'package:player_iptv/guia/xmltv.dart';

/// 23/11/2026 12:00 UTC.
const agora = 1795435200;

String hora(int segundos) {
  final d = DateTime.fromMillisecondsSinceEpoch(segundos * 1000, isUtc: true);
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${dois(d.month)}${dois(d.day)}${dois(d.hour)}${dois(d.minute)}00 +0000';
}

String programa(String canal, int ini, int fim, String titulo, [String desc = '']) =>
    '<programme start="${hora(ini)}" stop="${hora(fim)}" channel="$canal">'
    '<title lang="pt">$titulo</title>${desc.isEmpty ? '' : '<desc>$desc</desc>'}</programme>\n';

void main() {
  group('horaXmltv', () {
    test('com fuso: passa a UTC', () {
      expect(horaXmltv('20261123130000 +0100'), agora);
      expect(horaXmltv('20261123070000 -0500'), agora);
      expect(horaXmltv('20261123120000'), agora, reason: 'sem fuso é UTC');
      expect(horaXmltv('202611231200'), agora, reason: 'sem segundos');
      expect(horaXmltv('ontem'), isNull);
    });
  });

  test('textoXml: entidades, CDATA e etiquetas dentro', () {
    expect(textoXml('Tom &amp; Jerry &#233; &#xE9; &lt;3'), 'Tom & Jerry é é <3');
    expect(textoXml('<![CDATA[A & B]]>'), 'A & B');
    expect(textoXml('Jogo <b>em direto</b>'), 'Jogo em direto');
  });

  test('o leitor lê programas partidos entre bocados (até a meio de uma etiqueta)', () {
    final lidos = <ProgramaXmltv>[];
    final canais = <String, List<String>>{};
    final l = LeitorXmltv(aoPrograma: lidos.add, aoCanal: (id, n) => canais[id] = n);
    final xml = '<?xml version="1.0"?><tv><channel id="rtp1.pt"><display-name>RTP 1</display-name></channel>'
        '${programa('rtp1.pt', agora - 600, agora + 1200, 'Telejornal', 'As not&#237;cias')}'
        '${programa('sic.pt', agora, agora + 3600, 'Novela')}</tv>';
    for (var i = 0; i < xml.length; i += 7) {
      l.juntar(xml.substring(i, i + 7 > xml.length ? xml.length : i + 7));
    }
    expect(canais, {'rtp1.pt': ['RTP 1']});
    expect(lidos.map((p) => (p.canal, p.titulo, p.descricao)), [
      ('rtp1.pt', 'Telejornal', 'As notícias'),
      ('sic.pt', 'Novela', ''),
    ]);
    expect(lidos.first.inicio, agora - 600);
  });

  group('lerXmltv (só a janela útil dos canais da lista)', () {
    Future<(Map<String, List<Programa>>, bool)> ler(List<int> bytes,
        {List<(String, String, String)> canais = const [('10', 'rtp1.pt', 'RTP 1')], int maxBytes = 1 << 30,
        int bloco = 1000}) async {
      final porCanal = <String, List<Programa>>{};
      final ligacao = LigacaoCanais([for (final c in canais) c.$1], [for (final c in canais) c.$2],
          [for (final c in canais) c.$3]);
      Stream<List<int>> partes() async* {
        for (var i = 0; i < bytes.length; i += bloco) {
          yield bytes.sublist(i, i + bloco > bytes.length ? bytes.length : i + bloco);
        }
      }

      final cortado = await lerXmltv(partes(), ligacao, porCanal, agora: agora, maxBytes: maxBytes);
      return (porCanal, cortado);
    }

    String guia(String corpo) => '<tv>$corpo</tv>';

    test('fica o que está a dar e o que vem nas próximas horas; o resto vai fora', () async {
      final (r, cortado) = await ler(utf8.encode(guia([
        programa('rtp1.pt', agora - 7200, agora - 3600, 'Já acabou'),
        programa('rtp1.pt', agora - 600, agora + 1200, 'A dar'),
        programa('rtp1.pt', agora + 1200, agora + 3000, 'A seguir'),
        programa('rtp1.pt', agora + 20 * 3600, agora + 21 * 3600, 'Amanhã'),
        programa('outro.pt', agora, agora + 3600, 'De outro canal'),
      ].join())));
      expect(cortado, isFalse);
      expect(r.keys, ['10']);
      expect(r['10']!.map((p) => p.titulo), ['A dar', 'A seguir']);
    });

    test('no máximo 5 programas por canal, os mais próximos; títulos e descrições cortados', () async {
      final longo = 'x' * 1000;
      final (r, _) = await ler(utf8.encode(guia([
        for (var i = 7; i >= 0; i--) programa('rtp1.pt', agora + i * 1800, agora + (i + 1) * 1800, 'P$i', longo),
      ].join())));
      expect(r['10']!.map((p) => p.titulo), ['P0', 'P1', 'P2', 'P3', 'P4']);
      expect(r['10']!.first.descricao.length, maxDescricao);
    });

    test('um .xml.gz sem Content-Encoding também se lê', () async {
      final (r, _) = await ler(gzip.encode(utf8.encode(guia(programa('rtp1.pt', agora, agora + 60, 'Gz')))));
      expect(r['10']!.single.titulo, 'Gz');
    });

    test('sem id do guia: liga-se pelo nome do <channel> ou pelo id ("RTP1.pt")', () async {
      final (r, _) = await ler(
        utf8.encode(guia('<channel id="c1"><display-name>PT: SIC HD</display-name></channel>'
            '${programa('c1', agora, agora + 60, 'Pelo nome')}${programa('RTP1.pt', agora, agora + 60, 'Pelo id')}')),
        canais: [('20', '', 'SIC'), ('30', '', 'PT | RTP1 FHD')],
      );
      expect(r['20']!.single.titulo, 'Pelo nome');
      expect(r['30']!.single.titulo, 'Pelo id');
    });

    test('maior do que o limite: pára e fica o que se leu', () async {
      final corpo = [for (var i = 0; i < 400; i++) programa('rtp1.pt', agora + i * 60, agora + i * 60 + 60, 'P$i')].join();
      final (r, cortado) = await ler(utf8.encode(guia(corpo)), maxBytes: 5000, bloco: 1000);
      expect(cortado, isTrue);
      expect(r['10'], isNotEmpty);
    });
  });

  test('nomeComparavel junta as variantes do mesmo canal', () {
    expect(nomeComparavel('PT: RTP 1 HD'), 'rtp1');
    expect(nomeComparavel('RTP1'), 'rtp1');
    expect(nomeComparavel('SIC Notícias FHD'), 'sicnoticias');
  });
}
