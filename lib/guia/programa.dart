/// A programação (EPG) dos canais: os programas de cada canal, guardados de forma compacta.
library;

import '../modelo/canal.dart';

/// Um programa de um canal. As horas são segundos desde 1970 (UTC).
class Programa {
  const Programa(this.inicio, this.fim, this.titulo, [this.descricao = '']);

  final int inicio;
  final int fim;
  final String titulo;
  final String descricao;

  DateTime get horaInicio => DateTime.fromMillisecondsSinceEpoch(inicio * 1000);
  DateTime get horaFim => DateTime.fromMillisecondsSinceEpoch(fim * 1000);

  /// A dar no instante `agora` (segundos).
  bool aDar(int agora) => inicio <= agora && agora < fim;

  /// Quanto já passou (0–1) no instante `agora`.
  double progresso(int agora) => fim <= inicio ? 0 : ((agora - inicio) / (fim - inicio)).clamp(0.0, 1.0);

  /// A forma guardada: [início, fim, título, descrição].
  List<Object> paraLista() => [inicio, fim, titulo, descricao];

  static Programa? deLista(Object? l) {
    if (l is! List || l.length < 3) return null;
    final i = l[0], f = l[1];
    if (i is! num || f is! num) return null;
    return Programa(i.toInt(), f.toInt(), '${l[2]}', l.length > 3 ? '${l[3]}' : '');
  }

  @override
  bool operator ==(Object other) =>
      other is Programa && other.inicio == inicio && other.fim == fim && other.titulo == titulo &&
      other.descricao == descricao;

  @override
  int get hashCode => Object.hash(inicio, fim, titulo, descricao);

  @override
  String toString() => 'Programa($titulo, $inicio–$fim)';
}

/// Quanto se guarda de cada programa e de cada canal (o guia nunca cresce sem limite).
const maxTitulo = 120;
const maxDescricao = 300;
const maxProgramasPorCanal = 5;

/// A janela guardada: o que acaba depois de agora e começa nas próximas [horasJanela] horas.
const horasJanela = 8;

/// Corta um texto a `max` caracteres (com reticências) e tira os espaços a mais.
String cortarTexto(String t, int max) {
  final s = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
}

/// Junta `p` aos programas de um canal: ordenados pelo início, sem repetidos e só os
/// [maxProgramasPorCanal] primeiros (os mais próximos de agora).
void juntarPrograma(List<Programa> lista, Programa p) {
  if (lista.any((x) => x.inicio == p.inicio)) return;
  var i = lista.length;
  while (i > 0 && lista[i - 1].inicio > p.inicio) {
    i--;
  }
  if (i >= maxProgramasPorCanal) return;
  lista.insert(i, p);
  if (lista.length > maxProgramasPorCanal) lista.removeLast();
}

/// Um programa entra na janela guardada (acaba depois de `agora` e começa antes do fim da janela)?
bool naJanela(int inicio, int fim, int agora) =>
    fim > agora && inicio < agora + horasJanela * 3600 && fim > inicio;

/// O programa a dar e o seguinte, entre os de um canal (`agora` em segundos).
(Programa?, Programa?) agoraESeguinte(List<Programa> ps, int agora) {
  for (var i = 0; i < ps.length; i++) {
    final p = ps[i];
    if (p.aDar(agora)) return (p, i + 1 < ps.length ? ps[i + 1] : null);
    if (p.inicio > agora) return (null, p);
  }
  return (null, null);
}

/// O guia de uma lista: os programas por id do canal ([Canal.id]).
class GuiaLista {
  GuiaLista(this.porCanal, {required this.criado, this.etag = '', this.modificado = ''});

  GuiaLista.vazio() : this({}, criado: DateTime.fromMillisecondsSinceEpoch(0));

  final Map<String, List<Programa>> porCanal;

  /// Quando se descarregou (para saber quando atualizar).
  DateTime criado;

  /// O ETag e o Last-Modified do servidor (para não descarregar o que não mudou).
  final String etag;
  final String modificado;

  /// Até quando o guia tem programação (segundos; 0 = vazio).
  int get cobreAte {
    var m = 0;
    for (final ps in porCanal.values) {
      for (final p in ps) {
        if (p.fim > m) m = p.fim;
      }
    }
    return m;
  }

  bool get vazio => porCanal.isEmpty;

  Map<String, Object> paraJson() => {
        'v': 1,
        'criado': criado.millisecondsSinceEpoch,
        if (etag.isNotEmpty) 'etag': etag,
        if (modificado.isNotEmpty) 'lm': modificado,
        'c': {for (final e in porCanal.entries) e.key: [for (final p in e.value) p.paraLista()]},
      };

  static GuiaLista? deJson(Object? j) {
    if (j is! Map || j['v'] != 1) return null;
    final c = j['c'];
    if (c is! Map) return null;
    final porCanal = <String, List<Programa>>{};
    for (final e in c.entries) {
      final v = e.value;
      if (v is! List) continue;
      final ps = [for (final x in v) ?Programa.deLista(x)];
      if (ps.isNotEmpty) porCanal['${e.key}'] = ps;
    }
    final criado = j['criado'];
    return GuiaLista(porCanal,
        criado: DateTime.fromMillisecondsSinceEpoch(criado is num ? criado.toInt() : 0),
        etag: j['etag'] is String ? j['etag'] as String : '',
        modificado: j['lm'] is String ? j['lm'] as String : '');
  }

  /// Os programas guardados num mapa vindo de outro isolate ({id: [[início, fim, título, descrição]]}).
  static Map<String, List<Programa>> deMapa(Map m) => {
        for (final e in m.entries)
          if (e.value is List) '${e.key}': [for (final x in e.value as List) ?Programa.deLista(x)],
      };
}

/// Um nome de canal pronto para comparar: sem acentos, maiúsculas, o prefixo do país ("PT: ",
/// "PT | "), a qualidade no fim ("HD", "FHD", "4K") e o que não é letra ou algarismo.
String nomeComparavel(String nome) {
  var s = semAcentos(nome.trim());
  s = s.replaceFirst(RegExp(r'^[a-z]{2,3}\s*[:|]\s*'), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'\s+(uhd|fhd|hd|sd|hevc|h265|4k|1080p?|720p?)$'), '');
  return s.replaceAll(' ', '');
}
