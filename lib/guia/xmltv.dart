/// Leitura de um guia XMLTV aos bocados: o ficheiro nunca fica inteiro na memória, cada
/// `<programme>` é tratado logo que chega e o resto vai fora.
library;

/// Um `<programme>` lido: o canal (o id do XMLTV), as horas (segundos UTC), o título e a descrição.
typedef ProgramaXmltv = ({String canal, int inicio, int fim, String titulo, String descricao});

/// Recebe o texto do XMLTV aos bocados ([juntar]) e avisa a cada canal e programa completos.
class LeitorXmltv {
  LeitorXmltv({required this.aoPrograma, this.aoCanal});

  final void Function(ProgramaXmltv p) aoPrograma;

  /// Um `<channel id="…">` com os `<display-name>` (para ligar canais sem id de guia pelo nome).
  final void Function(String id, List<String> nomes)? aoCanal;

  /// Um elemento por fechar maior do que isto é lixo: deita-se fora (a memória fica limitada).
  static const maxElemento = 1 << 20;

  String _resto = '';

  void juntar(String bloco) {
    final s = _resto.isEmpty ? bloco : _resto + bloco;
    _resto = '';
    var pos = 0;
    while (true) {
      final iP = s.indexOf('<programme', pos);
      final iC = aoCanal == null ? -1 : s.indexOf('<channel', pos);
      final i = iP < 0 ? iC : (iC < 0 ? iP : (iP < iC ? iP : iC));
      if (i < 0) {
        // pode ficar meio "<programme" no fim do bloco
        final guardar = s.length - pos < 16 ? pos : s.length - 16;
        _resto = s.substring(guardar);
        return;
      }
      final programa = i == iP;
      final fecho = programa ? '</programme>' : '</channel>';
      final fim = s.indexOf(fecho, i);
      if (fim < 0) {
        _resto = s.length - i > maxElemento ? '' : s.substring(i);
        return;
      }
      final elemento = s.substring(i, fim);
      if (programa) {
        _programa(elemento);
      } else {
        _canal(elemento);
      }
      pos = fim + fecho.length;
    }
  }

  void _programa(String e) {
    final abertura = e.substring(0, _fimAbertura(e));
    final a = atributos(abertura);
    final canal = a['channel'] ?? '';
    final inicio = horaXmltv(a['start'] ?? ''), fim = horaXmltv(a['stop'] ?? '');
    if (canal.isEmpty || inicio == null || fim == null) return;
    aoPrograma((
      canal: canal,
      inicio: inicio,
      fim: fim,
      titulo: _texto(e, 'title'),
      descricao: _texto(e, 'desc'),
    ));
  }

  void _canal(String e) {
    final id = atributos(e.substring(0, _fimAbertura(e)))['id'] ?? '';
    if (id.isEmpty) return;
    final nomes = [
      for (final m in RegExp(r'<display-name[^>]*>([\s\S]*?)</display-name>').allMatches(e)) textoXml(m[1]!),
    ];
    aoCanal!(id, nomes);
  }

  static int _fimAbertura(String e) {
    final i = e.indexOf('>');
    return i < 0 ? e.length : i;
  }

  static String _texto(String e, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>([\\s\\S]*?)</$tag>').firstMatch(e);
    return m == null ? '' : textoXml(m[1]!);
  }
}

final _reAtributo = RegExp(r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');

/// Os atributos de uma etiqueta de abertura.
Map<String, String> atributos(String abertura) => {
      for (final m in _reAtributo.allMatches(abertura)) m[1]!: textoXml(m[2] ?? m[3] ?? ''),
    };

final _reEntidade = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');
final _reCdata = RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>');

/// O texto de um elemento: sem CDATA, sem etiquetas dentro e com as entidades trocadas.
String textoXml(String t) {
  var s = t.replaceAllMapped(_reCdata, (m) => m[1]!.replaceAll('&', '&amp;').replaceAll('<', '&lt;'));
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  return s.replaceAllMapped(_reEntidade, (m) {
    final e = m[1]!;
    switch (e) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
    }
    final n = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
    return n == null || n <= 0 || n > 0x10FFFF ? '' : String.fromCharCode(n);
  }).trim();
}

final _reHora = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{2}:?\d{2})?');

/// "20261123203000 +0100" → segundos UTC. Sem fuso, é UTC. Ilegível → null.
int? horaXmltv(String t) {
  final m = _reHora.firstMatch(t.trim());
  if (m == null) return null;
  int n(int i) => int.parse(m[i]!);
  final utc = DateTime.utc(n(1), n(2), n(3), n(4), n(5), m[6] == null ? 0 : n(6));
  var segundos = utc.millisecondsSinceEpoch ~/ 1000;
  final fuso = m[7]?.replaceAll(':', '');
  if (fuso != null) {
    final sinal = fuso.startsWith('-') ? -1 : 1;
    final h = int.parse(fuso.substring(1, 3)), mi = int.parse(fuso.substring(3, 5));
    segundos -= sinal * (h * 3600 + mi * 60);
  }
  return segundos;
}
