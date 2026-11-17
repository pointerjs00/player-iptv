import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ui/player/configuracao_mpv.dart';
import 'biblioteca.dart' show escreverAtomico;

/// Como a imagem ocupa o ecrã.
enum FormatoImagem {
  /// Imagem inteira, com barras se o formato não for o do ecrã.
  ajustar('ajustar', 'Ajustar'),

  /// Enche o ecrã sem deformar (corta as pontas).
  preencher('preencher', 'Preencher'),

  /// Enche o ecrã deformando a imagem.
  esticar('esticar', 'Esticar'),

  /// Força 16:9 (canais com o formato mal marcado).
  r16x9('16:9', '16:9'),

  /// Força 4:3.
  r4x3('4:3', '4:3'),

  /// Aumenta a imagem ajustada em 25 % (tira as barras pretas gravadas na própria imagem).
  zoom('zoom', 'Zoom');

  const FormatoImagem(this.nome, this.rotulo);

  /// O nome guardado nas preferências.
  final String nome;

  /// O texto mostrado.
  final String rotulo;

  static FormatoImagem deNome(String? n) => values.firstWhere((f) => f.nome == n, orElse: () => ajustar);
}

/// As preferências da app (`preferencias.json`), partilhadas pelo player (aqui), pela
/// verificação e pelo ecrã de Definições. Valem para todos os canais, no Android e no Windows.
///
/// No Windows a janela principal e a janela do player (o mesmo exe com `--player`) têm cada
/// uma a sua cópia e gravam no mesmo ficheiro: cada uma grava só as chaves que mudou, relê o
/// ficheiro antes de gravar e usa um ficheiro temporário único; [recarregar] apanha o que a
/// outra janela gravou. A velocidade não é preferência: cada canal começa a 1×.
class Preferencias extends ChangeNotifier {
  Preferencias._(this._pasta, {required bool tv}) : _ajustarTaxaEcra = tv;

  /// Sem ficheiro (testes, ou antes de [abrir]): os valores por omissão.
  Preferencias.omissao({bool tv = false}) : this._(null, tv: tv);

  /// As preferências em uso (abertas no arranque, em `main`).
  static Preferencias atual = Preferencias.omissao();

  static const nomeFicheiro = 'preferencias.json';

  /// O tempo limite da verificação por omissão e os seus limites, em segundos.
  static const padraoTimeoutVerificacao = 8, minTimeoutVerificacao = 5, maxTimeoutVerificacao = 30;

  /// O ficheiro da v1 (só tinha a descodificação e a taxa do ecrã): lido se não houver o novo.
  static const _antigo = 'preferencias_player.json';

  final Directory? _pasta;

  bool _desentrelacar = true;
  FormatoImagem _formato = FormatoImagem.ajustar;
  bool _hardware = true;
  double _volume = 100;
  ModoDescodificacao _modoAndroid = ModoDescodificacao.direto;
  bool _ajustarTaxaEcra;
  int _timeoutVerificacao = padraoTimeoutVerificacao;
  String _userAgent = '';

  /// As chaves mudadas aqui e ainda não gravadas: só essas se escrevem (as outras são da outra janela).
  final _sujas = <String>{};

  /// Desentrelaçamento (ligado por omissão): mpv `deinterlace=auto`, só nas imagens
  /// entrelaçadas. Sem efeito na descodificação direta do Android (o aparelho trata disso).
  bool get desentrelacar => _desentrelacar;
  set desentrelacar(bool v) => _mudar('desentrelacar', _desentrelacar != v, () => _desentrelacar = v);

  FormatoImagem get formato => _formato;
  set formato(FormatoImagem v) => _mudar('formato', _formato != v, () => _formato = v);

  /// Descodificação por hardware (desligada = software, para aparelhos com problemas).
  bool get hardware => _hardware;
  set hardware(bool v) => _mudar('hardware', _hardware != v, () => _hardware = v);

  /// Volume do player, 0–100.
  double get volume => _volume;
  set volume(double v) {
    final n = v.clamp(0, 100).toDouble();
    _mudar('volume', _volume != n, () => _volume = n);
  }

  /// Descodificação por hardware no Android: direta (por omissão) ou "Compatível".
  ModoDescodificacao get modoAndroid => _modoAndroid;
  set modoAndroid(ModoDescodificacao v) => _mudar('modoAndroid', _modoAndroid != v, () => _modoAndroid = v);

  /// "Ajustar a taxa do ecrã ao canal" (ligada por omissão na TV).
  bool get ajustarTaxaEcra => _ajustarTaxaEcra;
  set ajustarTaxaEcra(bool v) => _mudar('ajustarTaxaEcra', _ajustarTaxaEcra != v, () => _ajustarTaxaEcra = v);

  /// O tempo limite da verificação de cada canal, em segundos (5–30; 8 por omissão). A 2.ª
  /// volta das inconclusivas usa o dobro.
  int get timeoutVerificacao => _timeoutVerificacao;
  set timeoutVerificacao(int v) {
    final n = v.clamp(minTimeoutVerificacao, maxTimeoutVerificacao);
    _mudar('timeoutVerificacao', _timeoutVerificacao != n, () => _timeoutVerificacao = n);
  }

  /// O user-agent personalizado ('' = o por omissão): só nos pedidos M3U e Xtream (o Stalker
  /// mantém o do MAG). Sem quebras de linha nem caracteres de controlo (é um cabeçalho HTTP).
  String get userAgent => _userAgent;
  set userAgent(String v) {
    var n = v.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (n.length > 200) n = n.substring(0, 200);
    _mudar('userAgent', _userAgent != n, () => _userAgent = n);
  }

  void _mudar(String chave, bool mudou, VoidCallback f) {
    if (!mudou) return;
    f();
    _sujas.add(chave);
    notifyListeners();
  }

  /// Nunca lança: sem ficheiro, ficheiro estragado ou valores de outro tipo dão os valores
  /// por omissão (só os campos estragados; o ficheiro estragado fica guardado como `.bak`).
  static Future<Preferencias> abrir(Directory pasta, {bool tv = false}) async {
    final p = Preferencias._(pasta, tv: tv);
    for (final nome in const [nomeFicheiro, _antigo]) {
      final f = _ficheiro(pasta, nome);
      try {
        if (!await f.exists()) continue;
        var estragado = false;
        try {
          final lido = jsonDecode(utf8.decode(await f.readAsBytes()));
          if (lido is Map) {
            estragado = !p._ler(lido);
          } else {
            estragado = true;
          }
        } on FormatException {
          estragado = true;
        }
        if (estragado) await f.copy('${f.path}.bak');
      } catch (_) {
        // não se lê/copia: fica-se pelos valores por omissão
      }
      return p; // o primeiro ficheiro que existe é o que vale
    }
    return p;
  }

  /// Lê os campos do mapa; false se algum tinha o tipo errado (esse fica por omissão).
  /// [lidas] recebe as chaves lidas com sucesso.
  bool _ler(Map m, [Set<String>? lidas]) {
    var ok = true;
    T? campo<T>(String chave) {
      final v = m[chave];
      if (v == null) return null;
      if (v is T) {
        lidas?.add(chave);
        return v;
      }
      ok = false;
      return null;
    }

    _desentrelacar = campo<bool>('desentrelacar') ?? _desentrelacar;
    final formato = campo<String>('formato');
    if (formato != null) _formato = FormatoImagem.deNome(formato);
    _hardware = campo<bool>('hardware') ?? _hardware;
    final volume = campo<num>('volume');
    if (volume != null) _volume = volume.clamp(0, 100).toDouble();
    final modo = campo<String>('modoAndroid');
    if (modo != null) _modoAndroid = ModoDescodificacao.deNome(modo);
    _ajustarTaxaEcra = campo<bool>('ajustarTaxaEcra') ?? _ajustarTaxaEcra;
    final tempo = campo<num>('timeoutVerificacao');
    if (tempo != null) {
      _timeoutVerificacao = tempo.toInt().clamp(minTimeoutVerificacao, maxTimeoutVerificacao);
    }
    final ua = campo<String>('userAgent');
    if (ua != null) _userAgent = (Preferencias.omissao()..userAgent = ua)._userAgent;
    return ok;
  }

  Map<String, Object> _mapa() => {
        'desentrelacar': _desentrelacar,
        'formato': _formato.nome,
        'hardware': _hardware,
        'volume': _volume,
        'modoAndroid': _modoAndroid.nome,
        'ajustarTaxaEcra': _ajustarTaxaEcra,
        'timeoutVerificacao': _timeoutVerificacao,
        'userAgent': _userAgent,
      };

  /// Todas as definições, para a cópia de segurança.
  Map<String, Object> paraJson() => _mapa();

  /// Aplica as definições de um mapa (cópia de segurança): só as chaves conhecidas e com o
  /// tipo certo mudam; ficam por gravar ([guardar]).
  void aplicar(Map m) {
    final lidas = <String>{};
    final outro = Preferencias.omissao(tv: _ajustarTaxaEcra).._ler(m, lidas);
    if (lidas.contains('desentrelacar')) desentrelacar = outro._desentrelacar;
    if (lidas.contains('formato')) formato = outro._formato;
    if (lidas.contains('hardware')) hardware = outro._hardware;
    if (lidas.contains('volume')) volume = outro._volume;
    if (lidas.contains('modoAndroid')) modoAndroid = outro._modoAndroid;
    if (lidas.contains('ajustarTaxaEcra')) ajustarTaxaEcra = outro._ajustarTaxaEcra;
    if (lidas.contains('timeoutVerificacao')) timeoutVerificacao = outro._timeoutVerificacao;
    if (lidas.contains('userAgent')) userAgent = outro._userAgent;
  }

  /// O mapa do ficheiro (vazio se não existe ou está estragado). Lança [FileSystemException] se
  /// o ficheiro existe mas está bloqueado (a outra janela a trocá-lo): quem chama repete.
  static Future<Map<String, Object?>> _lerFicheiro(File f) async {
    final List<int> bytes;
    try {
      bytes = await f.readAsBytes();
    } on PathNotFoundException {
      return {};
    }
    try {
      final lido = jsonDecode(utf8.decode(bytes));
      if (lido is Map) return {for (final e in lido.entries) '${e.key}': e.value};
    } on FormatException {
      // estragado: parte-se do zero
    }
    return {};
  }

  /// Repete [f] enquanto o ficheiro estiver bloqueado pela outra janela (Windows).
  static Future<T> _repetir<T>(Future<T> Function() f) async {
    for (var tentativa = 1;; tentativa++) {
      try {
        return await f();
      } on FileSystemException {
        if (tentativa >= 8) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 15 * tentativa));
      }
    }
  }

  /// Relê o ficheiro (gravado por outra janela) e aplica o que lá está, exceto o que mudou aqui
  /// e ainda não foi gravado. A janela do player chama-o ao abrir cada canal.
  Future<void> recarregar() async {
    final pasta = _pasta;
    if (pasta == null) return;
    final Map<String, Object?> m;
    try {
      m = await _repetir(() => _lerFicheiro(_ficheiro(pasta, nomeFicheiro)));
    } on FileSystemException {
      return; // bloqueado de vez: fica-se com o que se tem
    }
    for (final k in _sujas) {
      m.remove(k);
    }
    final antes = jsonEncode(_mapa());
    _ler(m);
    if (jsonEncode(_mapa()) != antes) notifyListeners();
  }

  Future<void> _gravacao = Future.value();

  /// Grava (atómico: escreve ao lado, com um nome único por gravação, e troca). Relê o ficheiro
  /// e escreve só as chaves mudadas aqui (a outra janela pode ter gravado as dela); confirma
  /// depois que as suas chaves lá ficaram e repete se uma gravação em simultâneo as apagou.
  /// As gravações desta instância correm uma de cada vez; uma falha não impede as seguintes.
  Future<void> guardar() {
    final pasta = _pasta;
    if (pasta == null) return Future.value();
    final chaves = Set.of(_sujas);
    final valores = Map<String, Object>.of(_mapa())..removeWhere((k, _) => !chaves.contains(k));
    final feito = _gravacao.then((_) async {
      await pasta.create(recursive: true);
      final f = _ficheiro(pasta, nomeFicheiro);
      for (var tentativa = 0; tentativa < 4; tentativa++) {
        final m = await _repetir(() => _lerFicheiro(f))
          ..addAll(valores);
        await _repetir(() => escreverAtomico(f, jsonEncode(m)));
        final depois = await _repetir(() => _lerFicheiro(f));
        if (valores.entries.every((e) => depois[e.key] == e.value)) break;
      }
      // deixam de estar por gravar só as que ninguém mudou entretanto
      final agora = _mapa();
      for (final k in chaves) {
        if (agora[k] == valores[k]) _sujas.remove(k);
      }
    });
    _gravacao = feito.catchError((Object e) => debugPrint('preferências não gravadas ($e)'));
    return feito;
  }

  static File _ficheiro(Directory pasta, String nome) => File('${pasta.path}${Platform.pathSeparator}$nome');
}
