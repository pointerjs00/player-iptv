import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'protocolo.dart';

const uaMag = 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) '
    'MAG254 stbapp ver: 4 rev: 2721 Safari/533.3';

/// Os headers de uma box MAG (porta de `mac_headers` em motor/stalker.py).
Map<String, String> macHeaders(String mac, String referer, [String? token]) => {
      'User-Agent': uaMag,
      'X-User-Agent': 'Model: MAG254; Link: WiFi',
      'Accept': '*/*',
      'Connection': 'Keep-Alive',
      'Cookie': 'mac=$mac; stb_lang=en; timezone=Europe/Lisbon',
      'Referer': referer,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

String limparCmd(String cmd) =>
    cmd.trim().replaceFirst(RegExp(r'^(ffmpeg|ffrt\d*|auto)\s+', caseSensitive: false), '').trim();

final _reStreamVazio = RegExp(r'([?&]stream=)(?=&|$)');

/// Painéis que devolvem `stream=` vazio no create_link: preenche-se com o stream do cmd do
/// canal ou, na falta dele, com o id do canal.
String preencherStream(String link, Canal canal) {
  if (!_reStreamVazio.hasMatch(link)) return link;
  final original = Uri.tryParse(limparCmd(canal.cmd));
  var sid = original?.queryParameters['stream'] ?? '';
  if (sid.isEmpty) sid = canal.id.trim();
  if (sid.isEmpty) return link;
  return link.replaceFirstMapped(_reStreamVazio, (m) => '${m[1]}${Uri.encodeComponent(sid)}');
}

const _meses = {
  'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6, 'july': 7,
  'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12,
};

/// "February 3, 2027, 12:42 am" -> "2027-02-03"; "Unlimited" -> "sem limite"; outra coisa -> "".
String validadeDoTexto(String texto) {
  final s = texto.trim();
  if (const {'unlimited', 'ilimitado', 'unlimited plan'}.contains(s.toLowerCase())) return 'sem limite';
  final m = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})').firstMatch(s);
  final mes = m == null ? null : _meses[m[1]!.toLowerCase()];
  if (m == null || mes == null) return '';
  final dia = int.parse(m[2]!), ano = int.parse(m[3]!);
  final d = DateTime(ano, mes, dia);
  if (d.month != mes || d.day != dia) return '';
  return '${ano.toString().padLeft(4, '0')}-${mes.toString().padLeft(2, '0')}-${dia.toString().padLeft(2, '0')}';
}

List _comoLista(Object? d) => d is Map ? d.values.toList() : (d is List ? d : const []);

class _Sessao {
  _Sessao(this.base, this.mac)
      : deviceId = sha1.convert(utf8.encode(mac)).toString().toUpperCase(),
        referer = '${base.substring(0, base.lastIndexOf('/', base.lastIndexOf('/') - 1))}/c/';

  final String base; // .../server/load.php ou .../c/portal.php
  final String mac;
  final String deviceId;
  final String referer;
  String token = '';

  Future<Object?> get(Map<String, String> params, {Cancelamento? cancelamento,
      Duration timeout = const Duration(seconds: 15)}) async {
    final q = {'type': 'stb', ...params, if (token.isNotEmpty && !params.containsKey('token')) 'token': token,
        'JsHttpRequest': '1-xml'};
    final dados = await obterJson('$base?${Uri(queryParameters: q).query}',
        headers: macHeaders(mac, referer, token), timeout: timeout, cancelamento: cancelamento);
    var d = dados;
    if (d is List && d.isNotEmpty) d = d.first;
    if (d is Map && d.containsKey('js')) return d['js'];
    return d is Map ? d : null;
  }
}

/// Portais Stalker (portal + MAC). Porta de `motor/stalker.py`.
class Stalker implements Protocolo {
  final _sessoes = <String, _Sessao>{};

  Future<_Sessao> _entrar(Conta conta, Cancelamento? cancelamento, Aviso? aviso) async {
    Object? ultimoErro;
    var todos404 = true;
    for (final base in endpointsStalker(conta.endereco)) {
      final s = _Sessao(base, conta.mac);
      aviso?.call('a ligar ao portal (${Uri.parse(base).path})');
      try {
        final hs = await s.get({'action': 'handshake', 'token': '', 'prehash': '0', 'mac': conta.mac,
            'sn': '', 'stb_type': 'MAG254', 'device_id': s.deviceId, 'device_id2': s.deviceId},
            cancelamento: cancelamento);
        if (hs is Map && '${hs['token'] ?? ''}'.isNotEmpty) {
          s.token = '${hs['token']}';
          // alguns painéis só dão canais depois do perfil
          try {
            await s.get({'action': 'get_profile', 'mac': conta.mac, 'sn': '', 'stb_type': 'MAG254',
                'device_id': s.deviceId, 'device_id2': s.deviceId, 'hd': '1', 'ver': ''},
                cancelamento: cancelamento);
          } on Cancelado {
            rethrow;
          } catch (_) {/* o perfil é opcional */}
          _sessoes[chave(conta)] = s;
          return s;
        }
        ultimoErro = ErroLista('o portal respondeu sem token');
        todos404 = false;
      } on Cancelado {
        rethrow;
      } catch (e) {
        ultimoErro = e;
        if (!(e is ErroHttp && e.status == 404)) todos404 = false;
      }
    }
    // só "todos 404" é prova: um 401/403 no handshake pode ser WAF ou bloqueio de IP
    if (todos404) throw ErroLista('portal não encontrado', definitivo: true);
    throw ErroLista('não foi possível entrar no portal: '
        '${ultimoErro == null ? 'sem resposta' : descreverErro(ultimoErro)}');
  }

  @override
  Future<ConteudoLista> abrir(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) async {
    final s = await _entrar(conta, cancelamento, aviso);
    final validade = await _validade(s, cancelamento);
    aviso?.call('a pedir as categorias');
    final generos = <String, String>{};
    try {
      for (final g in _comoLista(await s.get({'type': 'itv', 'action': 'get_genres'}, cancelamento: cancelamento))) {
        if (g is Map && '${g['id']}' != '*') generos['${g['id']}'] = '${g['title'] ?? ''}'.trim();
      }
    } on Cancelado {
      rethrow;
    } catch (_) {/* sem categorias: fica tudo em "Sem grupo" */}

    aviso?.call('a pedir a lista de canais');
    var dados = <Object?>[];
    var completa = true;
    Object? erro;
    try {
      final r = await s.get({'type': 'itv', 'action': 'get_all_channels'},
          cancelamento: cancelamento, timeout: const Duration(seconds: 60));
      if (r is Map) {
        dados = _comoLista(r['data']).cast<Object?>();
        // R10: só é a lista inteira se não anunciar mais canais do que trouxe
        completa = (int.tryParse('${r['total_items'] ?? 0}') ?? 0) <= dados.length;
      }
    } on Cancelado {
      rethrow;
    } catch (e) {
      erro = e; // há portais sem get_all_channels: lê-se página a página
    }
    if (dados.isEmpty) {
      final (paginas, fim, erroPaginas) = await _paginas(s, cancelamento, aviso);
      dados = paginas;
      completa = fim;
      erro = erroPaginas ?? erro;
    }
    if (dados.isEmpty) {
      if (erro != null) throw ErroLista('não foi possível listar os canais (${descreverErro(erro)})');
      throw ErroLista('o portal não devolveu canais');
    }

    final canais = <Canal>[];
    final usados = <String>{};
    for (final c in dados) {
      if (c is! Map) continue;
      final gid = '${c['tv_genre_id'] ?? ''}';
      var grupo = generos[gid] ?? '';
      if (grupo.isEmpty) grupo = 'Sem grupo';
      usados.add(grupo);
      canais.add(Canal(id: '${c['id'] ?? c['cmd']}', nome: '${c['name'] ?? ''}'.trim(), grupo: grupo,
          cmd: '${c['cmd'] ?? ''}', logo: '${c['logo'] ?? ''}', numero: numeroCanal(c['number'])));
    }
    final grupos = [for (final g in generos.values) if (usados.contains(g)) g];
    for (final g in usados) {
      if (!grupos.contains(g)) grupos.add(g);
    }
    return ConteudoLista(grupos, canais, validade: validade, completa: completa);
  }

  /// get_main_info: `end_date` (data) ou o campo `phone`, que muitos painéis usam para a
  /// validade ("February 3, 2027, 12:42 am" / "Unlimited"). Uma conta expirada é prova.
  Future<String> _validade(_Sessao s, Cancelamento? cancelamento) async {
    Object? info;
    try {
      info = await s.get({'type': 'account_info', 'action': 'get_main_info'}, cancelamento: cancelamento);
    } on Cancelado {
      rethrow;
    } catch (_) {
      return '';
    }
    if (info is! Map) return '';
    var validade = validadeDoTexto('${info['phone'] ?? ''}');
    final fim = '${info['end_date'] ?? ''}'.trim();
    if (fim.startsWith('0000')) return validade.isEmpty ? 'sem limite' : validade;
    final data = DateTime.tryParse(fim.length >= 10 ? fim.substring(0, 10) : fim);
    if (data == null) return validade;
    if (data.year < 2000) return validade.isEmpty ? 'sem limite' : validade;
    final iso = fim.substring(0, 10);
    final hoje = DateTime.now();
    if (data.isBefore(DateTime(hoje.year, hoje.month, hoje.day))) {
      throw ErroLista('conta expirada em $iso', definitivo: true);
    }
    return iso;
  }

  static const _maxPaginas = 400;

  /// Os canais página a página, se a lista foi lida até ao fim (porta de `_listar`) e o erro
  /// que a cortou.
  Future<(List<Object?>, bool, Object?)> _paginas(_Sessao s, Cancelamento? cancelamento, Aviso? aviso) async {
    final todos = <Object?>[];
    var pagina = 1, totalPaginas = 1;
    var totalConhecido = false;
    while (pagina <= totalPaginas) {
      if (pagina > _maxPaginas) return (todos, false, null);
      aviso?.call('a pedir os canais · página $pagina${totalPaginas > 1 && totalConhecido ? '/$totalPaginas' : ''}');
      final Object? itv;
      try {
        itv = await s.get({'type': 'itv', 'action': 'get_ordered_list', 'genre': '*',
            'force_ch_link_check': '', 'fav': '0', 'sortby': 'number', 'p': '$pagina'},
            cancelamento: cancelamento);
      } on Cancelado {
        rethrow;
      } catch (e) {
        return (todos, false, e);
      }
      if (itv is! Map) return (todos, false, null);
      final d = _comoLista(itv['data']);
      // página vazia antes do total anunciado: o portal cortou (ritmo, erro), não é o fim
      if (d.isEmpty) return (todos, !totalConhecido, null);
      if (pagina == 1) {
        final total = int.tryParse('${itv['total_items'] ?? 0}') ?? 0;
        final porPagina = int.tryParse('${itv['max_page_items'] ?? 14}') ?? 14;
        totalConhecido = total > 0 && porPagina > 0;
        totalPaginas = totalConhecido ? (total / porPagina).ceil() : _maxPaginas + 1;
      }
      todos.addAll(d);
      pagina++;
    }
    return (todos, true, null);
  }

  @override
  Future<FonteVideo> fonte(Conta conta, Canal canal, {Cancelamento? cancelamento}) async {
    for (var tentativa = 0; tentativa < 2; tentativa++) {
      // o token pode ter expirado: na 2.ª tentativa entra-se de novo
      final s = (tentativa == 0 ? _sessoes[chave(conta)] : null) ?? await _entrar(conta, cancelamento, null);
      Object? r;
      try {
        r = await s.get({'type': 'itv', 'action': 'create_link', 'cmd': canal.cmd, 'series': '',
            'forced_storage': 'undefined', 'disable_ad': '0', 'download': '0'}, cancelamento: cancelamento);
      } on Cancelado {
        rethrow;
      } catch (_) {
        if (tentativa == 0) continue;
        rethrow;
      }
      var link = r is Map ? limparCmd('${r['cmd'] ?? ''}') : '';
      if (link.isEmpty) {
        final original = limparCmd(canal.cmd);
        if (original.isEmpty || original.toLowerCase().contains('localhost')) {
          if (tentativa == 0) continue;
          throw ErroLista('o portal não devolveu o link do canal');
        }
        link = original;
      }
      return FonteVideo(preencherStream(link, canal), macHeaders(conta.mac, s.referer));
    }
    throw ErroLista('o portal não devolveu o link do canal');
  }
}
