/// De onde vem a programação de cada tipo de lista: o Xtream (`xmltv.php` para todos os canais
/// e `get_short_epg` para um) e o portal MAC (`get_epg_info` e `get_short_epg`). As listas M3U
/// não têm guia (por agora).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../protocolos/protocolo.dart';
import '../protocolos/stalker.dart';
import '../protocolos/xtream.dart';
import '../rede/http.dart';
import 'programa.dart';
import 'xmltv.dart';

/// O guia de todos os canais, como veio do servidor.
class ResultadoGuia {
  const ResultadoGuia(this.porCanal, {this.naoMudou = false, this.cortado = false, this.etag = '',
      this.modificado = ''});

  /// O servidor diz que o guia não mudou desde o que está guardado (304).
  const ResultadoGuia.naoMudou() : this(const {}, naoMudou: true);

  final Map<String, List<Programa>> porCanal;
  final bool naoMudou;

  /// O guia era maior do que o limite: ficou o que se leu até lá.
  final bool cortado;
  final String etag;
  final String modificado;
}

/// A programação de um tipo de lista.
abstract class FonteGuia {
  /// O guia de todos os `canais` (só a janela útil). `anterior` permite perguntar se mudou.
  Future<ResultadoGuia> todos(Conta conta, List<Canal> canais, {GuiaLista? anterior, Cancelamento? cancelamento});

  /// Os próximos programas de um canal.
  Future<List<Programa>> doCanal(Conta conta, Canal canal, {Cancelamento? cancelamento});

  /// A fonte do guia de uma conta; null = sem guia (M3U).
  static FonteGuia? para(Conta c) => switch (c.tipo) {
        Tipo.xtream => GuiaXtream(),
        Tipo.stalker => GuiaStalker(),
        Tipo.m3u => null,
      };
}

int _agora() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

int? _segundos(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
  return n != null && n > 0 ? n : null;
}

/// Os programas de uma lista de itens JSON (Xtream ou portal), na janela útil.
List<Programa> _programasDeItens(Iterable<Object?> itens, int agora,
    {required String titulo, required String descricao, bool base64 = false}) {
  final ps = <Programa>[];
  for (final x in itens) {
    if (x is! Map) continue;
    final ini = _segundos(x['start_timestamp']), fim = _segundos(x['stop_timestamp'] ?? x['end_timestamp']);
    if (ini == null || fim == null || !naJanela(ini, fim, agora)) continue;
    String texto(Object? v) => base64 ? deBase64('${v ?? ''}') : '${v ?? ''}';
    final t = cortarTexto(texto(x[titulo]), maxTitulo);
    if (t.isEmpty) continue;
    juntarPrograma(ps, Programa(ini, fim, t, cortarTexto(texto(x[descricao]), maxDescricao)));
  }
  return ps;
}

/// O texto de um campo em base64 (o Xtream manda assim os títulos); se não for base64, fica como está.
String deBase64(String t) {
  final s = t.trim();
  if (s.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(base64.normalize(s)), allowMalformed: false);
  } on FormatException {
    return s;
  }
}

/// Os itens de uma resposta: uma lista, um mapa (os valores) ou `{data: …}`.
List<Object?> _itens(Object? r) {
  var d = r;
  if (d is Map && d['data'] != null) d = d['data'];
  if (d is Map && d['epg_listings'] != null) d = d['epg_listings'];
  if (d is List) return d;
  if (d is Map) return d.values.toList();
  return const [];
}

class GuiaXtream implements FonteGuia {
  GuiaXtream({this.agora = _agora, this.maxBytes = 150 * 1024 * 1024, this.prazo = const Duration(minutes: 3)});

  final int Function() agora;

  /// O máximo descarregado do `xmltv.php` (o resto fica de fora, e o guia fica "cortado").
  final int maxBytes;

  /// O tempo máximo da descarga inteira.
  final Duration prazo;

  @override
  Future<ResultadoGuia> todos(Conta conta, List<Canal> canais, {GuiaLista? anterior, Cancelamento? cancelamento}) {
    final q = Uri(queryParameters: {'username': conta.utilizador, 'password': conta.password}).query;
    return lerXmltvNumIsolate(
      '${Xtream.raiz(conta)}/xmltv.php?$q',
      canais,
      headers: {
        'User-Agent': uaListas(),
        if (anterior != null && anterior.etag.isNotEmpty) 'If-None-Match': anterior.etag,
        if (anterior != null && anterior.modificado.isNotEmpty) 'If-Modified-Since': anterior.modificado,
      },
      agora: agora(),
      maxBytes: maxBytes,
      prazo: prazo,
      cancelamento: cancelamento,
    );
  }

  @override
  Future<List<Programa>> doCanal(Conta conta, Canal canal, {Cancelamento? cancelamento}) async {
    final r = await Xtream.api(conta, {'action': 'get_short_epg', 'stream_id': canal.id, 'limit': '$maxProgramasPorCanal'},
        cancelamento, timeout: const Duration(seconds: 15));
    return _programasDeItens(_itens(r), agora(), titulo: 'title', descricao: 'description', base64: true);
  }
}

class GuiaStalker implements FonteGuia {
  GuiaStalker({this.agora = _agora, this.stalker});

  final int Function() agora;
  final Stalker? stalker;
  Stalker _portal(Conta c) => stalker ?? Protocolo.para(c) as Stalker;

  @override
  Future<ResultadoGuia> todos(Conta conta, List<Canal> canais, {GuiaLista? anterior, Cancelamento? cancelamento}) async {
    final r = await _portal(conta).pedir(conta, {'type': 'itv', 'action': 'get_epg_info', 'period': '$horasJanela'},
        cancelamento: cancelamento, timeout: const Duration(seconds: 60));
    final ids = {for (final c in canais) c.id};
    final t = agora();
    final porCanal = <String, List<Programa>>{};
    var d = r;
    if (d is Map && d['data'] != null) d = d['data'];
    if (d is Map) {
      for (final e in d.entries) {
        final id = '${e.key}';
        final v = e.value;
        if (!ids.contains(id) || v is! List) continue;
        final ps = _programasDeItens(v, t, titulo: 'name', descricao: 'descr');
        if (ps.isNotEmpty) porCanal[id] = ps;
      }
    } else if (d is List) {
      // alguns portais mandam uma lista só, com o canal em cada programa
      final porId = <String, List<Object?>>{};
      for (final x in d) {
        if (x is Map) (porId['${x['ch_id'] ?? ''}'] ??= []).add(x);
      }
      for (final e in porId.entries) {
        if (!ids.contains(e.key)) continue;
        final ps = _programasDeItens(e.value, t, titulo: 'name', descricao: 'descr');
        if (ps.isNotEmpty) porCanal[e.key] = ps;
      }
    } else {
      throw ErroLista('o portal não devolveu o guia');
    }
    return ResultadoGuia(porCanal);
  }

  @override
  Future<List<Programa>> doCanal(Conta conta, Canal canal, {Cancelamento? cancelamento}) async {
    final r = await _portal(conta).pedir(conta, {'type': 'itv', 'action': 'get_short_epg', 'ch_id': canal.id,
        'size': '$maxProgramasPorCanal'}, cancelamento: cancelamento);
    return _programasDeItens(_itens(r), agora(), titulo: 'name', descricao: 'descr');
  }
}

// ---------------------------------------------------------------------------------------------
// XMLTV: descarregado e lido num isolate, aos bocados.

/// Liga os canais do XMLTV aos da lista: pelo id do guia ([Canal.epg]) e, sem ele, pelo nome.
class LigacaoCanais {
  LigacaoCanais(List<String> ids, List<String> epgs, List<String> nomes) {
    for (var i = 0; i < ids.length; i++) {
      final e = epgs[i].trim().toLowerCase();
      if (e.isNotEmpty) (_porEpg[e] ??= []).add(ids[i]);
      final n = nomeComparavel(nomes[i]);
      if (n.isNotEmpty) (_porNome[n] ??= []).add(ids[i]);
    }
  }

  final _porEpg = <String, List<String>>{};
  final _porNome = <String, List<String>>{};
  final _resolvidos = <String, List<String>>{};
  final _nomesXmltv = <String, List<String>>{};

  /// Um `<channel>` do XMLTV, com os nomes (antes dos programas dele).
  void canal(String id, List<String> nomes) => _nomesXmltv[id] = nomes;

  /// Os canais da lista de um id do XMLTV (vazio = nenhum).
  List<String> ids(String xmltv) => _resolvidos[xmltv] ??= _resolver(xmltv);

  List<String> _resolver(String xmltv) {
    final porEpg = _porEpg[xmltv.trim().toLowerCase()];
    if (porEpg != null) return porEpg;
    final r = <String>{};
    for (final n in _nomesXmltv[xmltv] ?? const <String>[]) {
      r.addAll(_porNome[nomeComparavel(n)] ?? const []);
    }
    if (r.isEmpty) {
      // ids como "RTP1.pt": o nome antes do país
      final semPais = xmltv.replaceFirst(RegExp(r'\.[A-Za-z]{2,3}$'), '');
      r.addAll(_porNome[nomeComparavel(semPais)] ?? const []);
    }
    return r.toList();
  }
}

/// Lê um XMLTV (os bytes, gzip ou não) e guarda só a janela útil dos canais da lista.
/// Devolve se foi cortado (passou de `maxBytes`).
Future<bool> lerXmltv(Stream<List<int>> bytes, LigacaoCanais ligacao, Map<String, List<Programa>> porCanal,
    {required int agora, int maxBytes = 150 * 1024 * 1024}) async {
  final leitor = LeitorXmltv(
    aoCanal: ligacao.canal,
    aoPrograma: (p) {
      if (!naJanela(p.inicio, p.fim, agora)) return;
      final ids = ligacao.ids(p.canal);
      if (ids.isEmpty) return;
      final titulo = cortarTexto(p.titulo, maxTitulo);
      if (titulo.isEmpty) return;
      final prog = Programa(p.inicio, p.fim, titulo, cortarTexto(p.descricao, maxDescricao));
      for (final id in ids) {
        juntarPrograma(porCanal[id] ??= [], prog);
      }
    },
  );
  final texto = const Utf8Decoder(allowMalformed: true).startChunkedConversion(_Texto(leitor));
  ByteConversionSink? destino;
  var lidos = 0;
  var cortado = false;
  final fim = Completer<void>();
  late StreamSubscription<List<int>> sub;
  sub = bytes.listen((bloco) {
    // o 1.º bloco diz se é gzip (um .xml.gz sem Content-Encoding)
    destino ??= bloco.length >= 2 && bloco[0] == 0x1f && bloco[1] == 0x8b
        ? gzip.decoder.startChunkedConversion(texto)
        : texto;
    lidos += bloco.length;
    try {
      destino!.add(bloco);
    } catch (e) {
      // gzip estragado: fica o que se leu
      if (!fim.isCompleted) fim.complete();
      unawaited(sub.cancel());
      return;
    }
    if (lidos > maxBytes) {
      cortado = true;
      unawaited(sub.cancel());
      if (!fim.isCompleted) fim.complete();
    }
  }, onError: (Object e) {
    // a ligação caiu (ou o prazo acabou) a meio: fica o que já se leu
    if (lidos > 0) cortado = true;
    if (!fim.isCompleted) lidos > 0 ? fim.complete() : fim.completeError(e);
  }, onDone: () {
    if (!fim.isCompleted) fim.complete();
  }, cancelOnError: true);
  await fim.future;
  if (!cortado) {
    try {
      destino?.close();
    } catch (_) {/* o fim do gzip veio estragado: fica o que se leu */}
  }
  return cortado;
}

class _Texto implements Sink<String> {
  _Texto(this.leitor);
  final LeitorXmltv leitor;
  @override
  void add(String data) => leitor.juntar(data);
  @override
  void close() {}
}

class _PedidoXmltv {
  _PedidoXmltv(this.url, this.headers, this.ids, this.epgs, this.nomes, this.agora, this.maxBytes, this.prazo,
      this.porta);
  final String url;
  final Map<String, String> headers;
  final List<String> ids, epgs, nomes;
  final int agora, maxBytes;
  final Duration prazo;
  final SendPort porta;
}

/// Descarrega e lê o XMLTV de `url` num isolate próprio (a interface não engasga) e devolve só
/// a janela útil dos `canais`. Cancelar mata o isolate (a descarga pára logo).
Future<ResultadoGuia> lerXmltvNumIsolate(String url, List<Canal> canais,
    {Map<String, String> headers = const {}, required int agora, int maxBytes = 150 * 1024 * 1024,
    Duration prazo = const Duration(minutes: 3), Cancelamento? cancelamento}) async {
  cancelamento?.verificar();
  final porta = ReceivePort();
  final pedido = _PedidoXmltv(url, headers, [for (final c in canais) c.id], [for (final c in canais) c.epg],
      [for (final c in canais) c.nome], agora, maxBytes, prazo, porta.sendPort);
  final resposta = Completer<Object?>();
  final sub = porta.listen((m) {
    if (!resposta.isCompleted) resposta.complete(m);
  });
  Isolate? isolate;
  void Function()? pararDeOuvir;
  // cancelado enquanto o isolate ainda arranca: o erro fica guardado até ao await (não escapa)
  unawaited(resposta.future.then((_) {}, onError: (Object _) {}));
  if (cancelamento != null) {
    final filho = cancelamento.filho();
    pararDeOuvir = () => filho.cancelar();
    _aoCancelar(filho, () {
      isolate?.kill(priority: Isolate.immediate);
      if (!resposta.isCompleted) resposta.completeError(Cancelado());
    });
  }
  try {
    isolate = await Isolate.spawn(_lerXmltvIsolate, pedido, onExit: porta.sendPort, errorsAreFatal: true);
    if (cancelamento?.cancelado ?? false) isolate.kill(priority: Isolate.immediate);
    final r = await resposta.future;
    if (r is Map && r['erro'] != null) {
      final status = r['status'];
      if (status is int) throw ErroHttp(status, url);
      throw ErroLista('${r['erro']}');
    }
    if (r is! Map) throw ErroLista('a leitura do guia parou');
    if (r['naoMudou'] == true) return const ResultadoGuia.naoMudou();
    return ResultadoGuia(GuiaLista.deMapa(r['canais'] as Map), cortado: r['cortado'] == true,
        etag: '${r['etag'] ?? ''}', modificado: '${r['lm'] ?? ''}');
  } finally {
    pararDeOuvir?.call();
    await sub.cancel();
    porta.close();
  }
}

/// Chama `f` quando `c` for cancelado (o [Cancelamento] só avisa os filhos).
void _aoCancelar(Cancelamento c, void Function() f) {
  // espera pelo cancelamento sem prender nada: o esperarCancelavel acorda logo ao cancelar
  unawaited(esperarCancelavel(const Duration(days: 1), c).then((_) {}, onError: (Object e) {
    if (e is Cancelado) f();
  }));
}

Future<void> _lerXmltvIsolate(_PedidoXmltv p) async {
  try {
    p.porta.send(await _lerXmltvUrl(p));
  } catch (e) {
    p.porta.send({'erro': e is ErroHttp ? 'o servidor respondeu ${e.status}' : '$e',
        if (e is ErroHttp) 'status': e.status});
  }
}

Future<Map<String, Object?>> _lerXmltvUrl(_PedidoXmltv p) async {
  final cliente = HttpClient()
    ..autoUncompress = true
    ..connectionTimeout = const Duration(seconds: 30);
  final prazo = Timer(p.prazo, () => cliente.close(force: true));
  try {
    final pedido = await cliente.getUrl(Uri.parse(p.url));
    pedido.followRedirects = true;
    p.headers.forEach((k, v) => pedido.headers.set(k, v, preserveHeaderCase: true));
    final resp = await pedido.close().timeout(const Duration(seconds: 30));
    if (resp.statusCode == 304) {
      await resp.drain<void>().catchError((_) {});
      return {'naoMudou': true};
    }
    if (resp.statusCode >= 400) {
      await resp.drain<void>().catchError((_) {});
      throw ErroHttp(resp.statusCode, p.url);
    }
    final porCanal = <String, List<Programa>>{};
    final cortado = await lerXmltv(resp.timeout(const Duration(seconds: 30)), LigacaoCanais(p.ids, p.epgs, p.nomes),
        porCanal, agora: p.agora, maxBytes: p.maxBytes);
    return {
      'canais': {for (final e in porCanal.entries) e.key: [for (final x in e.value) x.paraLista()]},
      'cortado': cortado,
      'etag': resp.headers.value('etag') ?? '',
      'lm': resp.headers.value('last-modified') ?? '',
    };
  } finally {
    prazo.cancel();
    cliente.close(force: true);
  }
}
