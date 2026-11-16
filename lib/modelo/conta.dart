/// Modelo de conta (o mesmo do verificador: Accounts.json do sfvip), chave de
/// deduplicação e nome da lista. Porta de `tv-management/motor/conta.py`.
library;

enum Tipo { stalker, xtream, m3u }

const camposConta = [
  'Name', 'Address', 'Mac', 'Username', 'Password', 'SerialNumber', 'DeviceID',
  'DeviceID2', 'Firmware', 'StbModel', 'TimeZone', 'UserAgent', 'ForceUserAgent',
];

/// Prefixo das inconclusivas no export.
const marcaInc = 'INC ';

class Conta {
  Conta(this.nome, this.tipo, this.endereco,
      {this.mac = '', this.utilizador = '', this.password = '', this.original});

  final String nome;
  final Tipo tipo;
  final String endereco;
  final String mac;
  final String utilizador;
  final String password;

  /// O dict de onde veio (Accounts.json), para o export manter os outros campos.
  final Map<String, dynamic>? original;

  Map<String, dynamic> paraJson() => {
        'nome': nome, 'tipo': tipo.name, 'endereco': endereco, 'mac': mac,
        'utilizador': utilizador, 'password': password,
        if (original != null) 'original': original,
      };

  static Conta deJson(Map<String, dynamic> j) => Conta(
        '${j['nome'] ?? ''}', Tipo.values.byName('${j['tipo']}'), '${j['endereco']}',
        mac: '${j['mac'] ?? ''}', utilizador: '${j['utilizador'] ?? ''}',
        password: '${j['password'] ?? ''}',
        original: j['original'] is Map ? Map<String, dynamic>.from(j['original'] as Map) : null,
      );
}

String _txt(Object? v) => v is String ? v.trim() : '';

final _reMac = RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

/// O host de um URL (sem porta), '' se não der para ler.
String hostDe(String url) {
  final u = Uri.tryParse(url.contains('://') ? url : 'http://$url');
  return u?.host ?? '';
}

/// (raiz, user, pass) se `url` for um get.php com credenciais; senão null.
(String, String, String)? xtreamDeUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !u.path.toLowerCase().contains('get.php')) return null;
  final q = {for (final e in u.queryParameters.entries) e.key.toLowerCase(): e.value};
  final user = q['username'] ?? '', pw = q['password'] ?? '';
  if (user.isEmpty || pw.isEmpty) return null;
  return ('${u.scheme}://${u.authority}', user, pw);
}

Conta? contaDeDict(Object? d) {
  if (d is! Map) return null;
  final end = _txt(d['Address']);
  if (end.isEmpty) return null;
  final nome = _txt(d['Name']);
  final mac = _txt(d['Mac']).toUpperCase();
  final user = _txt(d['Username']), pw = _txt(d['Password']);
  final orig = Map<String, dynamic>.from(d);
  if (mac.isNotEmpty) {
    return Conta(nome, Tipo.stalker, end, mac: mac, utilizador: user, password: pw, original: orig);
  }
  final x = xtreamDeUrl(end);
  if (user.isNotEmpty && pw.isNotEmpty) {
    // um get.php completo no Address fica pela raiz: a mesma conta tem a mesma chave
    return Conta(nome, Tipo.xtream, x?.$1 ?? end, utilizador: user, password: pw, original: orig);
  }
  if (x != null) return Conta(nome, Tipo.xtream, x.$1, utilizador: x.$2, password: x.$3, original: orig);
  return Conta(nome, Tipo.m3u, end, original: orig);
}

Conta? contaDeLinha(String linha) {
  final partes = linha.trim().split(RegExp(r'\s+'));
  if (partes.isEmpty || !RegExp(r'^https?://', caseSensitive: false).hasMatch(partes[0])) {
    return null;
  }
  final url = partes[0];
  if (partes.length > 1 && _reMac.hasMatch(partes[1])) {
    return Conta(hostDe(url), Tipo.stalker, url, mac: partes[1].toUpperCase());
  }
  final x = xtreamDeUrl(url);
  if (x != null) return Conta(hostDe(url), Tipo.xtream, x.$1, utilizador: x.$2, password: x.$3);
  return Conta(hostDe(url), Tipo.m3u, url);
}

const _sufixos = ['/c/portal.php', '/server/load.php', '/portal.php', '/c/', '/c', '/'];

/// O caminho de um portal Stalker sem /c/, /portal.php, /server/load.php... no fim.
String caminhoPortal(String caminho) {
  var mudou = true;
  while (mudou) {
    mudou = false;
    for (final s in _sufixos) {
      if (caminho.toLowerCase().endsWith(s)) {
        caminho = caminho.substring(0, caminho.length - s.length);
        mudou = true;
        break;
      }
    }
  }
  return caminho;
}

/// Os dois endpoints a tentar num portal Stalker.
List<String> endpointsStalker(String endereco) {
  final u = Uri.parse(endereco.trim());
  final raiz = '${u.scheme}://${u.authority}';
  final c = caminhoPortal(u.path);
  return ['$raiz$c/server/load.php', '$raiz$c/c/portal.php'];
}

String _enderecoChave(Conta c) {
  var end = c.endereco.trim();
  if (!end.contains('://')) end = 'http://$end';
  final u = Uri.tryParse(end);
  if (u == null || u.host.isEmpty) return end.toLowerCase().replaceAll(RegExp(r'/+$'), '');
  final esquema = u.scheme.toLowerCase();
  var host = u.host.toLowerCase();
  // Uri põe a porta por omissão (80/443) em u.port; só se mantém uma porta explícita diferente
  if (u.hasPort && !((esquema == 'http' && u.port == 80) || (esquema == 'https' && u.port == 443))) {
    host = '$host:${u.port}';
  }
  var caminho = u.path;
  if (c.tipo == Tipo.stalker) {
    caminho = caminhoPortal(caminho);
  } else if (c.tipo == Tipo.m3u && u.hasQuery) {
    caminho = '$caminho?${u.query}';
  }
  return '$esquema://$host${caminho.replaceAll(RegExp(r'/+$'), '')}';
}

/// Identifica a lista: duas contas com a mesma chave são a mesma lista.
String chave(Conta c) {
  var end = _enderecoChave(c);
  if (c.tipo != Tipo.m3u) end = end.toLowerCase();
  return '${c.tipo.name}|$end|${c.mac.toUpperCase()}|${c.utilizador}';
}

List<Conta> deduplicar(Iterable<Conta> contas) {
  final vistas = <String>{};
  return [for (final c in contas) if (vistas.add(chave(c))) c];
}

final _reData = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _reIp = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');

/// Nº de ordem (3 algarismos) + host até ao 1.º ponto + espaço + validade DDMMAA.
/// Ex.: 3, http://nxtbox.uk/c/, 2027-10-16 -> "003NXTBOX 161027". Sem data: "003NXTBOX".
String nomeLista(int n, Conta c, [String validade = '']) {
  var host = hostDe(c.endereco).toLowerCase();
  if (host.startsWith('www.')) host = host.substring(4);
  final base = (_reIp.hasMatch(host) || host.contains(':')) ? host : host.split('.').first;
  var nome = '${n.toString().padLeft(3, '0')}${(base.isEmpty ? 'lista' : base).toUpperCase()}';
  final m = _reData.firstMatch(validade);
  if (m != null) nome += ' ${m[3]}${m[2]}${m[1]!.substring(2)}';
  return nome;
}

/// O link testado: Stalker = portal; Xtream = get.php; M3U = a lista.
String linkConta(Conta c) {
  if (c.tipo == Tipo.xtream) {
    if (xtreamDeUrl(c.endereco) != null) return c.endereco;
    final q = Uri(queryParameters: {
      'username': c.utilizador, 'password': c.password, 'type': 'm3u_plus', 'output': 'ts',
    }).query;
    return '${c.endereco.replaceAll(RegExp(r'/+$'), '')}/get.php?$q';
  }
  return c.endereco;
}

/// O dict Accounts.json da conta (mantém os campos do original).
Map<String, dynamic> contaParaDict(Conta c) {
  final o = c.original;
  if (o != null && o.isNotEmpty) {
    return {for (final k in camposConta) k: o[k] ?? (k == 'ForceUserAgent' ? false : '')};
  }
  return {
    for (final k in camposConta) k: k == 'ForceUserAgent' ? false : '',
    'Name': c.nome, 'Address': c.endereco, 'Mac': c.mac,
    'Username': c.utilizador, 'Password': c.password,
  };
}
