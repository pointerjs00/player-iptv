/// Conteúdo de uma lista: grupos (categorias) e canais.
library;

class Canal {
  const Canal({
    required this.id,
    required this.nome,
    required this.grupo,
    this.url = '',
    this.logo = '',
    this.cmd = '',
    this.userAgent,
    this.referer,
  });

  /// Identificador estável dentro da lista (id do portal ou o URL).
  final String id;
  final String nome;
  final String grupo;

  /// M3U / Xtream: o URL do stream. Stalker: vazio (o link vem do create_link).
  final String url;
  final String logo;

  /// Stalker: o `cmd` do canal (pede-se o link com ele).
  final String cmd;
  final String? userAgent;
  final String? referer;

  Map<String, dynamic> paraJson() => {
        'id': id, 'nome': nome, 'grupo': grupo, 'url': url, 'logo': logo, 'cmd': cmd,
        if (userAgent != null) 'ua': userAgent,
        if (referer != null) 'referer': referer,
      };

  static Canal deJson(Map<String, dynamic> j) => Canal(
        id: '${j['id']}', nome: '${j['nome']}', grupo: '${j['grupo']}', url: '${j['url'] ?? ''}',
        logo: '${j['logo'] ?? ''}', cmd: '${j['cmd'] ?? ''}',
        userAgent: j['ua'] as String?, referer: j['referer'] as String?,
      );
}

class ConteudoLista {
  ConteudoLista(this.grupos, this.canais, {this.validade = '', this.completa = true, this.limiteLigacoes = ''});

  /// False se o portal não deixou ler a lista inteira (limite de páginas, página vazia ou com
  /// erro antes do fim, `total_items` maior do que os canais recebidos): um canal que não
  /// aparece não prova nada.
  final bool completa;

  /// Xtream: "ativas/máximo" quando `active_cons >= max_connections` (explica uma falha).
  final String limiteLigacoes;

  /// "AAAA-MM-DD", "sem limite" ou "" (desconhecida).
  final String validade;

  /// Pela ordem do portal/lista.
  final List<String> grupos;
  final List<Canal> canais;

  List<Canal> doGrupo(String g) => [for (final c in canais) if (c.grupo == g) c];

  Map<String, int> contagens() {
    final m = <String, int>{};
    for (final c in canais) {
      m[c.grupo] = (m[c.grupo] ?? 0) + 1;
    }
    return m;
  }

  Map<String, dynamic> paraJson() => {
        'grupos': grupos, 'canais': [for (final c in canais) c.paraJson()], 'validade': validade,
      };

  static ConteudoLista deJson(Map<String, dynamic> j) => ConteudoLista(
        [for (final g in (j['grupos'] as List? ?? const [])) '$g'],
        [for (final c in (j['canais'] as List? ?? const [])) Canal.deJson(Map<String, dynamic>.from(c as Map))],
        validade: '${j['validade'] ?? ''}',
      );
}

/// O que o player precisa para abrir um canal.
class FonteVideo {
  const FonteVideo(this.url, [this.headers = const {}]);
  final String url;
  final Map<String, String> headers;
}

/// Texto sem acentos e em minúsculas, para pesquisar ("joao" encontra "João").
String semAcentos(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    b.writeCharCode(_semAcento[r] ?? r);
  }
  return b.toString();
}

final Map<int, int> _semAcento = () {
  const de = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
  const para = 'aaaaaaceeeeiiiinooooouuuuyy';
  return {for (var i = 0; i < de.length; i++) de.codeUnitAt(i): para.codeUnitAt(i)};
}();
