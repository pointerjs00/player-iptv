import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'protocolo.dart';

/// Contas Xtream (`player_api.php`). Porta de `motor/xtream.py`.
class Xtream implements Protocolo {
  final _extensoes = <String, String>{};

  String _raiz(Conta c) {
    final u = Uri.parse(c.endereco.trim());
    return '${u.scheme}://${u.authority}';
  }

  Future<Object?> _api(Conta c, Map<String, String> extra, Cancelamento? cancelamento) {
    final q = Uri(queryParameters: {'username': c.utilizador, 'password': c.password, ...extra}).query;
    return obterJson('${_raiz(c)}/player_api.php?$q', headers: const {'User-Agent': uaVlc},
        timeout: const Duration(seconds: 30), cancelamento: cancelamento);
  }

  /// "ts", ou "m3u8" quando o servidor diz que ts não é permitido mas m3u8 é.
  static String extensao(Map userInfo) {
    var f = userInfo['allowed_output_formats'];
    if (f is String) f = f.split(',');
    if (f is! List) return 'ts';
    final fs = {for (final x in f) '$x'.trim().toLowerCase()};
    return !fs.contains('ts') && fs.contains('m3u8') ? 'm3u8' : 'ts';
  }

  /// "AAAA-MM-DD", "sem limite" (exp_date nulo/0) ou "" (sem campo ou ilegível).
  static String validadeXtream(Map userInfo) {
    if (!userInfo.containsKey('exp_date')) return '';
    final exp = '${userInfo['exp_date'] ?? ''}'.trim();
    final epoch = exp.isEmpty ? 0 : double.tryParse(exp)?.toInt();
    if (epoch == null) return '';
    if (epoch <= 0) return 'sem limite';
    final d = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static int? _numero(Object? v) => double.tryParse('${v ?? ''}'.trim())?.toInt();

  /// "ativas/máximo" se `active_cons >= max_connections` (máximo > 0), senão "" (`_limite_atingido`).
  static String limiteAtingido(Map userInfo) {
    final ativas = _numero(userInfo['active_cons']), maximo = _numero(userInfo['max_connections']);
    return ativas != null && maximo != null && maximo > 0 && ativas >= maximo ? '$ativas/$maximo' : '';
  }

  /// Uma resposta HTTP da API (401/403/404...) pode ser WAF, geo, IP ou proxy: não prova que
  /// a conta morreu (`_falha_api`). Só o JSON `user_info` prova.
  Future<Object?> _apiSemProva(Conta c, Map<String, String> extra, Cancelamento? cancelamento,
      String Function(String motivo) mensagem) async {
    try {
      return await _api(c, extra, cancelamento);
    } on ErroHttp catch (e) {
      throw ErroLista(mensagem('a API respondeu ${e.status}'));
    }
  }

  @override
  Future<ConteudoLista> abrir(Conta conta, {Cancelamento? cancelamento, Aviso? aviso}) async {
    aviso?.call('a entrar na conta');
    final info = await _apiSemProva(conta, const {}, cancelamento, (m) => m);
    final user = info is Map ? info['user_info'] : null;
    if (user is! Map) throw ErroLista('o servidor não respondeu como um painel Xtream');
    if (!user.containsKey('auth')) throw ErroLista('resposta do servidor sem estado de autenticação');
    if (!const {'1', 'true'}.contains('${user['auth']}'.toLowerCase())) {
      throw ErroLista('autenticação recusada', definitivo: true);
    }
    final status = '${user['status'] ?? 'active'}'.toLowerCase();
    if (status != 'active') throw ErroLista('conta ${user['status']}', definitivo: true);
    final validade = validadeXtream(user);
    final fim = DateTime.tryParse(validade);
    if (fim != null && fim.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      throw ErroLista('conta expirada em $validade', definitivo: true);
    }
    _extensoes[chave(conta)] = extensao(user);

    aviso?.call('a pedir as categorias');
    Object? cats;
    try {
      cats = await _api(conta, const {'action': 'get_live_categories'}, cancelamento);
    } on Cancelado {
      rethrow;
    } catch (_) {/* sem categorias: fica tudo em "Sem grupo" */}
    final nomes = <String, String>{};
    final grupos = <String>[];
    if (cats is List) {
      for (final c in cats) {
        if (c is! Map) continue;
        final nome = '${c['category_name'] ?? ''}'.trim();
        nomes['${c['category_id']}'] = nome.isEmpty ? 'Sem grupo' : nome;
      }
    }
    aviso?.call('a pedir os canais');
    final streams = await _apiSemProva(conta, const {'action': 'get_live_streams'}, cancelamento,
        (m) => 'não foi possível listar os canais ($m)');
    if (streams is! List) throw ErroLista('o servidor não devolveu a lista de canais');
    final canais = <Canal>[];
    final vistos = <String>{};
    for (final s in streams) {
      if (s is! Map || s['stream_id'] == null) continue;
      final grupo = nomes['${s['category_id']}'] ?? 'Sem grupo';
      if (vistos.add(grupo)) grupos.add(grupo);
      canais.add(Canal(id: '${s['stream_id']}', nome: '${s['name'] ?? ''}'.trim(), grupo: grupo,
          logo: '${s['stream_icon'] ?? ''}'));
    }
    // a ordem das categorias do painel, com as que não têm canais no fim
    final ordem = [for (final n in nomes.values) if (vistos.contains(n)) n];
    for (final g in grupos) {
      if (!ordem.contains(g)) ordem.add(g);
    }
    return ConteudoLista(ordem.toSet().toList(), canais, validade: validade, limiteLigacoes: limiteAtingido(user));
  }

  @override
  Future<FonteVideo> fonte(Conta conta, Canal canal, {Cancelamento? cancelamento}) async {
    final ext = _extensoes[chave(conta)] ?? 'ts';
    final u = Uri.encodeComponent(conta.utilizador), p = Uri.encodeComponent(conta.password);
    return FonteVideo('${_raiz(conta)}/live/$u/$p/${Uri.encodeComponent(canal.id)}.$ext',
        const {'User-Agent': uaVlc});
  }
}
