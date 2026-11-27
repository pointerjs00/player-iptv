/// FPB (Federação Portuguesa de Basquetebol): os jogos da Liga Betclic Masculina (spec §3, fase 2).
///   https://www.fpb.pt/calendario/?epoca=2026/2027&genero=masculino&escalao=Sénior
/// A página (HTML) traz os próximos jogos, cerca de três semanas, por dia («5 DEZ 2026»), cada
/// um com a hora de Lisboa («18H00»), as equipas e a competição. Os filtros de datas da página
/// fazem-se no browser: pede-se uma vez (cache de 24 h) e escolhe-se o dia aqui. Os dias que já
/// passaram não estão lá.
library;

import '../catalogo.dart';
import '../cliente_desporto.dart';
import '../hora_lisboa.dart';
import '../modelo.dart';

const _meses = {
  'JAN': 1, 'FEV': 2, 'MAR': 3, 'ABR': 4, 'MAI': 5, 'JUN': 6,
  'JUL': 7, 'AGO': 8, 'SET': 9, 'OUT': 10, 'NOV': 11, 'DEZ': 12,
};

final _data = RegExp(r'<h3 class="date">\s*(\d{1,2})\s+([A-Z]{3})\s+(\d{4})');
final _id = RegExp(r'internalID=(\d+)');
final _nome = RegExp(r'class="fullName">([^<]*)<');
final _hora = RegExp(r'<h3>\s*(\d{1,2})H(\d{2})');
final _emblema = RegExp(r'class="image-container">\s*<img[^>]*src="([^"]+)"');

String _texto(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Os jogos em `html` (a página do calendário) das competições `seguidas` com `fpb`.
List<Jogo> lerFpb(String html, Set<String> seguidas) {
  final comps = [
    for (final c in catalogoCompeticoes)
      if (c.fpb != null && seguidas.contains(c.id)) c,
  ];
  if (comps.isEmpty) return const [];
  final r = <Jogo>[];
  for (final dia in html.split('class="day-wrapper').skip(1)) {
    final d = _data.firstMatch(dia);
    final mes = d == null ? null : _meses[d.group(2)];
    if (d == null || mes == null) continue;
    for (final bloco in dia.split('<!-- END GAME ROW -->')) {
      final id = _id.firstMatch(bloco)?.group(1);
      final nomes = [for (final m in _nome.allMatches(bloco)) _texto(m.group(1)!)];
      final h = _hora.firstMatch(bloco);
      if (id == null || nomes.length < 2 || h == null) continue;
      Competicao? comp;
      for (final c in comps) {
        if (bloco.contains(c.fpb!)) comp = c;
      }
      if (comp == null) continue;
      final emblemas = [for (final m in _emblema.allMatches(bloco)) m.group(1)!];
      r.add(Jogo(
        id: 'fpb:$id',
        desporto: comp.desporto,
        competicaoId: comp.id,
        casa: nomes[0],
        fora: nomes[1],
        emblemaCasa: emblemas.elementAtOrNull(0),
        emblemaFora: emblemas.elementAtOrNull(1),
        inicio: lisboaParaUtc(DateTime(
            int.parse(d.group(3)!), mes, int.parse(d.group(1)!), int.parse(h.group(1)!), int.parse(h.group(2)!))),
      ));
    }
  }
  return r;
}

/// A época de basquetebol de `dia` («2026/2027»: de agosto a julho).
String epocaFpb(DateTime dia) => dia.month >= 8 ? '${dia.year}/${dia.year + 1}' : '${dia.year - 1}/${dia.year}';

/// Os jogos da FPB do dia `dia` (de Lisboa) das competições `seguidas`.
Future<Lido<List<Jogo>>> jogosFpb(ClienteDesporto c, DateTime dia, Set<String> seguidas,
    {bool soCache = false}) async {
  if (!catalogoCompeticoes.any((x) => x.fpb != null && seguidas.contains(x.id))) return const Lido(<Jogo>[]);
  final hoje = utcParaLisboa(c.agora());
  final uri = Uri.parse('https://www.fpb.pt/calendario/').replace(queryParameters: {
    'epoca': epocaFpb(hoje),
    'genero': 'masculino',
    'escalao': 'Sénior',
  });
  final r = await c.texto('fpb-calendario', uri, Validade.fpb, soCache: soCache);
  bool noDia(Jogo j) {
    final l = utcParaLisboa(j.inicio);
    return l.year == dia.year && l.month == dia.month && l.day == dia.day;
  }

  return Lido.de(r, (t) => [for (final j in lerFpb(t, seguidas)) if (noDia(j)) j], const <Jogo>[]);
}
