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

/// O desentrelaçamento do player (canais 1080i/576i/480i).
enum ModoDesentrelacamento {
  /// Só as imagens que o mpv vê entrelaçadas (o "ligado" de antes).
  automatico('automatico', 'Automático'),

  /// Todas as imagens, mesmo as que o mpv vê como progressivas (canais mal marcados).
  ligado('ligado', 'Ligado'),

  desligado('desligado', 'Desligado');

  const ModoDesentrelacamento(this.nome, this.rotulo);

  /// O nome guardado nas preferências.
  final String nome;

  /// O texto mostrado.
  final String rotulo;

  /// null: nome desconhecido.
  static ModoDesentrelacamento? deNome(String? n) => values.where((m) => m.nome == n).firstOrNull;
}

/// O tamanho da interface na TV e no Windows (no telemóvel fica sempre a 100 %).
enum TamanhoInterface {
  /// Toda a interface a 80 % (cabe mais em cada ecrã).
  compacto('Compacto'),

  /// O tamanho de antes.
  normal('Normal');

  const TamanhoInterface(this.rotulo);

  /// O texto mostrado (o nome guardado é o `name`).
  final String rotulo;

  static TamanhoInterface deNome(String? n) => values.firstWhere((t) => t.name == n, orElse: () => compacto);
}

/// O motor do player no Android (no Windows é sempre o mpv).
enum MotorAndroid {
  /// O ExoPlayer (Media3) numa `SurfaceView`: a imagem vai do descodificador para o ecrã.
  exoplayer('exoplayer', 'ExoPlayer'),

  /// O mpv (media_kit): desentrelaçamento, modo Compatível e descodificação por software.
  mpv('mpv', 'mpv');

  const MotorAndroid(this.nome, this.rotulo);

  /// O nome guardado nas preferências.
  final String nome;

  /// O texto mostrado.
  final String rotulo;

  /// Um nome desconhecido dá o ExoPlayer (a omissão).
  static MotorAndroid deNome(String? n) => values.firstWhere((m) => m.nome == n, orElse: () => exoplayer);
}

/// Como se recua no direto (Definições › Imagem e som › «Recuar no direto»).
enum RecuoDireto {
  /// O canal grava-se no armazenamento (até [Preferencias.reservaDiretoGb]) e apaga-se ao mudar de
  /// canal: recua-se e pausa-se minutos.
  armazenamento('armazenamento', 'Armazenamento'),

  /// Só o que o motor guarda em memória (o mpv, o seu cache; o ExoPlayer, um back buffer).
  memoria('memoria', 'Memória'),

  /// Sem gravar e sem back buffer no ExoPlayer (o mpv fica como sempre).
  desligado('desligado', 'Desligado');

  const RecuoDireto(this.nome, this.rotulo);

  /// O nome guardado nas preferências.
  final String nome;

  /// O texto mostrado.
  final String rotulo;

  /// Um nome desconhecido dá Armazenamento (a omissão).
  static RecuoDireto deNome(String? n) => values.firstWhere((r) => r.nome == n, orElse: () => armazenamento);
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

  /// Quanto se espera pelo bloqueio do ficheiro (outra janela a gravar) antes de desistir.
  static Duration esperaBloqueio = const Duration(seconds: 5);

  /// O tempo limite da verificação por omissão e os seus limites, em segundos.
  static const padraoTimeoutVerificacao = 8, minTimeoutVerificacao = 5, maxTimeoutVerificacao = 30;

  /// Quantas listas se verificam ao mesmo tempo (omissão e limites).
  static const padraoListasEmSimultaneo = 8, minListasEmSimultaneo = 1, maxListasEmSimultaneo = 20;

  /// O tempo limite de cada lista (todos os canais de teste), em segundos (omissão e limites).
  static const padraoTempoLimiteLista = 30, minTempoLimiteLista = 10, maxTempoLimiteLista = 300;

  /// O espaço reservado para o direto gravado, em GB (omissão e limites).
  static const padraoReservaDiretoGb = 2, minReservaDiretoGb = 1, maxReservaDiretoGb = 3;

  /// O ficheiro da v1 (só tinha a descodificação e a taxa do ecrã): lido se não houver o novo.
  static const _antigo = 'preferencias_player.json';

  final Directory? _pasta;

  ModoDesentrelacamento _modoDesentrelacamento = ModoDesentrelacamento.automatico;
  FormatoImagem _formato = FormatoImagem.ajustar;
  bool _hardware = true;
  double _volume = 100;
  ModoDescodificacao _modoAndroid = ModoDescodificacao.direto;
  bool _ajustarTaxaEcra;
  MotorAndroid _motorAndroid = MotorAndroid.exoplayer;
  bool _modoTunel = false;
  int _timeoutVerificacao = padraoTimeoutVerificacao;
  int _listasEmSimultaneo = padraoListasEmSimultaneo;
  int _tempoLimiteLista = padraoTempoLimiteLista;
  String _userAgent = '';
  TamanhoInterface _tamanhoInterface = TamanhoInterface.compacto;
  RecuoDireto _recuoDireto = RecuoDireto.armazenamento;
  int _reservaDiretoGb = padraoReservaDiretoGb;

  /// As chaves mudadas aqui e ainda não gravadas: só essas se escrevem (as outras são da outra janela).
  final _sujas = <String>{};

  /// Desentrelaçamento (Automático por omissão: só nas imagens entrelaçadas). Grava-se em
  /// `modo_desentrelacamento`; os ficheiros e as cópias antigas só têm `desentrelacar` (true =
  /// Automático, false = Desligado), que se continua a gravar para as versões anteriores da app.
  ModoDesentrelacamento get modoDesentrelacamento => _modoDesentrelacamento;
  set modoDesentrelacamento(ModoDesentrelacamento v) {
    if (_modoDesentrelacamento == v) return;
    _sujas.add('desentrelacar');
    _mudar(_chaveModoDesentrelacamento, true, () => _modoDesentrelacamento = v);
  }

  static const _chaveModoDesentrelacamento = 'modo_desentrelacamento';

  /// Há desentrelaçamento (Automático ou Ligado). Ligar (o interruptor das Definições) dá
  /// Automático, a não ser que já esteja Ligado.
  bool get desentrelacar => _modoDesentrelacamento != ModoDesentrelacamento.desligado;
  set desentrelacar(bool v) => modoDesentrelacamento = !v
      ? ModoDesentrelacamento.desligado
      : (desentrelacar ? _modoDesentrelacamento : ModoDesentrelacamento.automatico);

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

  /// O motor do player no Android (o ExoPlayer por omissão; no Windows é sempre o mpv).
  MotorAndroid get motorAndroid => _motorAndroid;
  set motorAndroid(MotorAndroid v) => _mudar('motorAndroid', _motorAndroid != v, () => _motorAndroid = v);

  /// O túnel de vídeo do ExoPlayer (desligado por omissão: só alguns aparelhos o suportam bem).
  bool get modoTunel => _modoTunel;
  set modoTunel(bool v) => _mudar('modoTunel', _modoTunel != v, () => _modoTunel = v);

  /// O tempo limite da verificação de cada canal, em segundos (5–30; 8 por omissão). A 2.ª
  /// volta das inconclusivas usa o dobro.
  int get timeoutVerificacao => _timeoutVerificacao;
  set timeoutVerificacao(int v) {
    final n = v.clamp(minTimeoutVerificacao, maxTimeoutVerificacao);
    _mudar('timeoutVerificacao', _timeoutVerificacao != n, () => _timeoutVerificacao = n);
  }

  /// Quantas listas se verificam ao mesmo tempo (1–20; 8 por omissão).
  int get listasEmSimultaneo => _listasEmSimultaneo;
  set listasEmSimultaneo(int v) {
    final n = v.clamp(minListasEmSimultaneo, maxListasEmSimultaneo);
    _mudar('listasEmSimultaneo', _listasEmSimultaneo != n, () => _listasEmSimultaneo = n);
  }

  /// O tempo limite de cada lista na verificação, em segundos (10–300; 30 por omissão).
  int get tempoLimiteLista => _tempoLimiteLista;
  set tempoLimiteLista(int v) {
    final n = v.clamp(minTempoLimiteLista, maxTempoLimiteLista);
    _mudar('tempoLimiteLista', _tempoLimiteLista != n, () => _tempoLimiteLista = n);
  }

  /// O user-agent personalizado ('' = o por omissão): só nos pedidos M3U e Xtream (o Stalker
  /// mantém o do MAG). Sem quebras de linha nem caracteres de controlo (é um cabeçalho HTTP).
  String get userAgent => _userAgent;
  set userAgent(String v) {
    var n = v.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    if (n.length > 200) n = n.substring(0, 200);
    _mudar('userAgent', _userAgent != n, () => _userAgent = n);
  }

  /// O tamanho da interface (Compacto por omissão): ver `escalaPara`.
  TamanhoInterface get tamanhoInterface => _tamanhoInterface;
  set tamanhoInterface(TamanhoInterface v) =>
      _mudar('tamanhoInterface', _tamanhoInterface != v, () => _tamanhoInterface = v);

  /// Como se recua no direto (Armazenamento por omissão).
  RecuoDireto get recuoDireto => _recuoDireto;
  set recuoDireto(RecuoDireto v) => _mudar('recuoDireto', _recuoDireto != v, () => _recuoDireto = v);

  /// O espaço reservado para o direto gravado, em GB (1–3; 2 por omissão). O gravado nunca passa
  /// disto (e baixa se o aparelho tiver pouco espaço livre).
  int get reservaDiretoGb => _reservaDiretoGb;
  set reservaDiretoGb(int v) {
    final n = v.clamp(minReservaDiretoGb, maxReservaDiretoGb);
    _mudar('reservaDiretoGb', _reservaDiretoGb != n, () => _reservaDiretoGb = n);
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

    final modoDeint = ModoDesentrelacamento.deNome(campo<String>(_chaveModoDesentrelacamento));
    final antigoDeint = campo<bool>('desentrelacar');
    if (modoDeint != null) {
      _modoDesentrelacamento = modoDeint;
    } else if (antigoDeint != null) {
      _modoDesentrelacamento = antigoDeint ? ModoDesentrelacamento.automatico : ModoDesentrelacamento.desligado;
    }
    final formato = campo<String>('formato');
    if (formato != null) _formato = FormatoImagem.deNome(formato);
    _hardware = campo<bool>('hardware') ?? _hardware;
    final volume = campo<num>('volume');
    if (volume != null) _volume = volume.clamp(0, 100).toDouble();
    final modo = campo<String>('modoAndroid');
    if (modo != null) _modoAndroid = ModoDescodificacao.deNome(modo);
    _ajustarTaxaEcra = campo<bool>('ajustarTaxaEcra') ?? _ajustarTaxaEcra;
    final motor = campo<String>('motorAndroid');
    if (motor != null) _motorAndroid = MotorAndroid.deNome(motor);
    _modoTunel = campo<bool>('modoTunel') ?? _modoTunel;
    final tempo = campo<num>('timeoutVerificacao');
    if (tempo != null) {
      _timeoutVerificacao = tempo.toInt().clamp(minTimeoutVerificacao, maxTimeoutVerificacao);
    }
    final simultaneo = campo<num>('listasEmSimultaneo');
    if (simultaneo != null) {
      _listasEmSimultaneo = simultaneo.toInt().clamp(minListasEmSimultaneo, maxListasEmSimultaneo);
    }
    final limiteLista = campo<num>('tempoLimiteLista');
    if (limiteLista != null) {
      _tempoLimiteLista = limiteLista.toInt().clamp(minTempoLimiteLista, maxTempoLimiteLista);
    }
    final ua = campo<String>('userAgent');
    if (ua != null) _userAgent = (Preferencias.omissao()..userAgent = ua)._userAgent;
    final tamanho = campo<String>('tamanhoInterface');
    if (tamanho != null) _tamanhoInterface = TamanhoInterface.deNome(tamanho);
    final recuo = campo<String>('recuoDireto');
    if (recuo != null) _recuoDireto = RecuoDireto.deNome(recuo);
    final reserva = campo<num>('reservaDiretoGb');
    if (reserva != null) _reservaDiretoGb = reserva.toInt().clamp(minReservaDiretoGb, maxReservaDiretoGb);
    return ok;
  }

  Map<String, Object> _mapa() => {
        _chaveModoDesentrelacamento: _modoDesentrelacamento.nome,
        'desentrelacar': desentrelacar,
        'formato': _formato.nome,
        'hardware': _hardware,
        'volume': _volume,
        'modoAndroid': _modoAndroid.nome,
        'ajustarTaxaEcra': _ajustarTaxaEcra,
        'motorAndroid': _motorAndroid.nome,
        'modoTunel': _modoTunel,
        'timeoutVerificacao': _timeoutVerificacao,
        'listasEmSimultaneo': _listasEmSimultaneo,
        'tempoLimiteLista': _tempoLimiteLista,
        'userAgent': _userAgent,
        'tamanhoInterface': _tamanhoInterface.name,
        'recuoDireto': _recuoDireto.nome,
        'reservaDiretoGb': _reservaDiretoGb,
      };

  /// Todas as definições, para a cópia de segurança.
  Map<String, Object> paraJson() => _mapa();

  /// Aplica as definições de um mapa (cópia de segurança): só as chaves conhecidas e com o
  /// tipo certo mudam; ficam por gravar ([guardar]).
  void aplicar(Map m) {
    final lidas = <String>{};
    final outro = Preferencias.omissao(tv: _ajustarTaxaEcra).._ler(m, lidas);
    if (lidas.contains(_chaveModoDesentrelacamento) || lidas.contains('desentrelacar')) {
      modoDesentrelacamento = outro._modoDesentrelacamento;
    }
    if (lidas.contains('formato')) formato = outro._formato;
    if (lidas.contains('hardware')) hardware = outro._hardware;
    if (lidas.contains('volume')) volume = outro._volume;
    if (lidas.contains('modoAndroid')) modoAndroid = outro._modoAndroid;
    if (lidas.contains('ajustarTaxaEcra')) ajustarTaxaEcra = outro._ajustarTaxaEcra;
    if (lidas.contains('motorAndroid')) motorAndroid = outro._motorAndroid;
    if (lidas.contains('modoTunel')) modoTunel = outro._modoTunel;
    if (lidas.contains('timeoutVerificacao')) timeoutVerificacao = outro._timeoutVerificacao;
    if (lidas.contains('listasEmSimultaneo')) listasEmSimultaneo = outro._listasEmSimultaneo;
    if (lidas.contains('tempoLimiteLista')) tempoLimiteLista = outro._tempoLimiteLista;
    if (lidas.contains('userAgent')) userAgent = outro._userAgent;
    if (lidas.contains('tamanhoInterface')) tamanhoInterface = outro._tamanhoInterface;
    if (lidas.contains('recuoDireto')) recuoDireto = outro._recuoDireto;
    if (lidas.contains('reservaDiretoGb')) reservaDiretoGb = outro._reservaDiretoGb;
  }

  /// O mapa do ficheiro: vazio se não existe, null se existe mas está estragado (não é um mapa
  /// JSON). Lança [FileSystemException] se está bloqueado (a outra janela a trocá-lo): quem
  /// chama repete.
  static Future<Map<String, Object?>?> _lerFicheiro(File f) async {
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
      // estragado
    }
    return null;
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
      m = await _repetir(() => _lerFicheiro(_ficheiro(pasta, nomeFicheiro))) ?? {};
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

  /// Fecha o ficheiro de bloqueio `preferencias.lock` (exclusivo, entre processos) à volta de
  /// [f]; espera até [esperaBloqueio] e lança [FileSystemException] se não o conseguir.
  static Future<T> _comBloqueio<T>(Directory pasta, Future<T> Function() f) async {
    await pasta.create(recursive: true);
    final raf = await _ficheiro(pasta, 'preferencias.lock').open(mode: FileMode.append);
    try {
      final limite = DateTime.now().add(esperaBloqueio);
      while (true) {
        try {
          await raf.lock(FileLock.exclusive);
          break;
        } on FileSystemException {
          if (DateTime.now().isAfter(limite)) {
            throw const FileSystemException('as preferências estão a ser gravadas por outra janela');
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      try {
        return await f();
      } finally {
        try {
          await raf.unlock();
        } on FileSystemException {
          // fechar o ficheiro também larga o bloqueio
        }
      }
    } finally {
      await raf.close();
    }
  }

  /// Grava (atómico: escreve ao lado, com um nome único por gravação, e troca), com o ficheiro
  /// bloqueado para os outros processos: lê, junta só as chaves mudadas aqui (a outra janela
  /// pode ter gravado as dela) e escreve. Se o ficheiro está estragado, guarda-o como `.bak` e
  /// escreve o estado completo. Se não consegue (bloqueio, disco), lança e as chaves continuam
  /// por gravar. As gravações desta instância correm uma de cada vez.
  Future<void> guardar() {
    final pasta = _pasta;
    if (pasta == null) return Future.value();
    final feito = _gravacao.then((_) async {
      final chaves = Set.of(_sujas);
      final valores = Map<String, Object>.of(_mapa())..removeWhere((k, _) => !chaves.contains(k));
      await _comBloqueio(pasta, () async {
        final f = _ficheiro(pasta, nomeFicheiro);
        var m = await _repetir(() => _lerFicheiro(f));
        if (m == null) {
          try {
            await f.copy('${f.path}.bak');
          } on FileSystemException {
            // sem cópia: escreve-se na mesma o estado completo
          }
          m = Map<String, Object?>.of(_mapa());
        }
        m.addAll(valores);
        await _repetir(() => escreverAtomico(f, jsonEncode(m)));
      });
      // deixam de estar por gravar só as que ninguém mudou entretanto
      final agora = _mapa();
      for (final k in chaves) {
        if (agora[k] == valores[k]) _sujas.remove(k);
      }
    });
    _gravacao = feito.then<void>((_) {}, onError: (Object e) => debugPrint('preferências não gravadas ($e)'));
    return feito;
  }

  static File _ficheiro(Directory pasta, String nome) => File('${pasta.path}${Platform.pathSeparator}$nome');
}
