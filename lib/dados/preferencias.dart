import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ui/player/configuracao_mpv.dart';

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
/// verificação e pelo ecrã de Definições. Valem para todos os canais, no Android e no Windows
/// (a janela do player do Windows lê o mesmo ficheiro). A velocidade não é preferência: cada
/// canal começa a 1×.
class Preferencias extends ChangeNotifier {
  Preferencias._(this._pasta, {required bool tv}) : _ajustarTaxaEcra = tv;

  /// Sem ficheiro (testes, ou antes de [abrir]): os valores por omissão.
  Preferencias.omissao({bool tv = false}) : this._(null, tv: tv);

  /// As preferências em uso (abertas no arranque, em `main`).
  static Preferencias atual = Preferencias.omissao();

  static const nomeFicheiro = 'preferencias.json';

  /// O ficheiro da v1 (só tinha a descodificação e a taxa do ecrã): lido se não houver o novo.
  static const _antigo = 'preferencias_player.json';

  final Directory? _pasta;

  bool _desentrelacar = true;
  FormatoImagem _formato = FormatoImagem.ajustar;
  bool _hardware = true;
  double _volume = 100;
  ModoDescodificacao _modoAndroid = ModoDescodificacao.direto;
  bool _ajustarTaxaEcra;

  /// Desentrelaçamento (ligado por omissão): mpv `deinterlace=auto`, só nas imagens
  /// entrelaçadas. Sem efeito na descodificação direta do Android (o aparelho trata disso).
  bool get desentrelacar => _desentrelacar;
  set desentrelacar(bool v) => _mudar(_desentrelacar != v, () => _desentrelacar = v);

  FormatoImagem get formato => _formato;
  set formato(FormatoImagem v) => _mudar(_formato != v, () => _formato = v);

  /// Descodificação por hardware (desligada = software, para aparelhos com problemas).
  bool get hardware => _hardware;
  set hardware(bool v) => _mudar(_hardware != v, () => _hardware = v);

  /// Volume do player, 0–100.
  double get volume => _volume;
  set volume(double v) {
    final n = v.clamp(0, 100).toDouble();
    _mudar(_volume != n, () => _volume = n);
  }

  /// Descodificação por hardware no Android: direta (por omissão) ou "Compatível".
  ModoDescodificacao get modoAndroid => _modoAndroid;
  set modoAndroid(ModoDescodificacao v) => _mudar(_modoAndroid != v, () => _modoAndroid = v);

  /// "Ajustar a taxa do ecrã ao canal" (ligada por omissão na TV).
  bool get ajustarTaxaEcra => _ajustarTaxaEcra;
  set ajustarTaxaEcra(bool v) => _mudar(_ajustarTaxaEcra != v, () => _ajustarTaxaEcra = v);

  void _mudar(bool mudou, VoidCallback f) {
    if (!mudou) return;
    f();
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
  bool _ler(Map m) {
    var ok = true;
    T? campo<T>(String chave) {
      final v = m[chave];
      if (v == null) return null;
      if (v is T) return v;
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
    return ok;
  }

  Map<String, Object> _mapa() => {
        'desentrelacar': _desentrelacar,
        'formato': _formato.nome,
        'hardware': _hardware,
        'volume': _volume,
        'modoAndroid': _modoAndroid.nome,
        'ajustarTaxaEcra': _ajustarTaxaEcra,
      };

  Future<void> _gravacao = Future.value();

  /// Grava (atómico: escreve ao lado e troca). As gravações correm uma de cada vez, pela
  /// ordem pedida; uma falha não impede as seguintes.
  Future<void> guardar() {
    final pasta = _pasta;
    if (pasta == null) return Future.value();
    final conteudo = jsonEncode(_mapa());
    final feito = _gravacao.then((_) async {
      await pasta.create(recursive: true);
      final f = _ficheiro(pasta, nomeFicheiro);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(conteudo);
      await tmp.rename(f.path);
    });
    _gravacao = feito.catchError((Object e) => debugPrint('preferências não gravadas ($e)'));
    return feito;
  }

  static File _ficheiro(Directory pasta, String nome) => File('${pasta.path}${Platform.pathSeparator}$nome');
}
