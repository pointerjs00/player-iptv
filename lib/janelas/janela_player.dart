/// Windows: o player corre numa janela própria — o mesmo .exe lançado com `--player <porta>`.
/// A janela principal abre um socket em 127.0.0.1 e manda-lhe linhas JSON:
///   principal → player: {"tipo":"abrir","lista":"001X","canais":[...],"i":3}
///   player → principal: {"tipo":"fonte","pedido":7,"i":4}
///   principal → player: {"tipo":"fonte","pedido":7,"url":"…","headers":{…}} ou {"…","erro":"…"}
/// O player, lançado com um token aleatório numa variável de ambiente, tem de mandar
/// primeiro {"tipo":"ola","token":"…"} (em 2 s); depois disso a principal deixa de aceitar
/// ligações até o player fechar. Outro processo da máquina não consegue pedir links.
/// Assim o link do canal (que no Stalker precisa da sessão do portal) é sempre pedido pela
/// janela principal, e trocar de canal na principal muda o canal na janela do player.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart';
import '../modelo/canal.dart';
import '../protocolos/protocolo.dart';
import '../rede/http.dart';

/// Lado da janela principal.
typedef LancarPlayer = Future<void> Function(int porta, String token);

class JanelaPlayer {
  JanelaPlayer._(this._lancar, {this.prazo = const Duration(seconds: 20)});
  static final instancia = JanelaPlayer._(_lancarProcesso);

  /// Para os testes: em vez de lançar o .exe, chama `lancar`.
  @visibleForTesting
  factory JanelaPlayer.paraTestes(LancarPlayer lancar, {Duration prazo = const Duration(seconds: 20)}) =>
      JanelaPlayer._(lancar, prazo: prazo);

  final LancarPlayer _lancar;

  /// Quanto se espera que a janela do player ligue depois de lançada.
  final Duration prazo;
  bool _aLancar = false;

  /// A variável de ambiente com o token do player (não vai no argv, que outros processos veem).
  static const variavelToken = 'PLAYER_IPTV_TOKEN';
  static const _maxLinha = 1024 * 1024;
  String _token = '';

  ServerSocket? _servidor;
  Socket? _ligacao;
  Lista? _lista;
  List<Canal> _canais = const [];
  Map<String, dynamic>? _pendente;
  void Function(Canal canal)? _aoVer;

  /// Mostra `canais[i]` na janela do player (abre-a se não estiver aberta).
  /// `aoVer` é chamado com cada canal que o player pede para abrir (o primeiro e os do zapping).
  Future<void> mostrar(Lista lista, List<Canal> canais, int i,
      {void Function(String motivo)? aoFalhar, void Function(Canal canal)? aoVer}) async {
    _lista = lista;
    _canais = canais;
    _aoVer = aoVer;
    final msg = {
      'tipo': 'abrir', 'lista': lista.nomeMostrado, 'i': i,
      'canais': [
        for (final c in canais) {'id': c.id, 'nome': c.nome, 'grupo': c.grupo, if (c.numero != null) 'num': c.numero},
      ],
    };
    if (_ligacao != null) {
      _enviar(msg);
      return;
    }
    _pendente = msg;
    if (_aLancar) return; // a abrir: a mensagem vai quando ligar
    _aLancar = true;
    final tentativa = ++_tentativa;
    try {
      _token = _novoToken();
      final srv = _servidor ??= await _abrirServidor();
      await _lancar(srv.port, _token);
    } catch (e) {
      // sem isto o player nunca mais abria até reiniciar a app
      _desistir();
      throw ErroLista('Não foi possível abrir o player (${descreverErro(e)}).');
    }
    // se a janela não ligar a tempo, desiste-se e avisa-se (o próximo clique tenta de novo)
    Timer(prazo, () {
      if (_ligacao != null || tentativa != _tentativa || !_aLancar) return;
      _desistir();
      aoFalhar?.call('A janela do player não abriu a tempo. Tente de novo.');
    });
  }

  int _tentativa = 0;

  void _desistir() {
    _aLancar = false;
    _pendente = null;
    _token = '';
  }

  static Future<void> _lancarProcesso(int porta, String token) async {
    await Process.start(Platform.resolvedExecutable, ['--player', '$porta'],
        mode: ProcessStartMode.detached, environment: {variavelToken: token});
  }

  static String _novoToken() {
    final r = Random.secure();
    return base64Url.encode(List.generate(32, (_) => r.nextInt(256)));
  }

  static bool _iguais(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }

  Future<ServerSocket> _abrirServidor() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen(_aceitar);
    return s;
  }

  void _aceitar(Socket sock) {
    if (_ligacao != null) {
      sock.destroy();
      return;
    }
    var autenticado = false;
    final prazo = Timer(const Duration(seconds: 2), () {
      if (!autenticado) sock.destroy();
    });
    void fim() {
      prazo.cancel();
      sock.destroy();
      if (identical(_ligacao, sock)) {
        _ligacao = null;
        _aLancar = false;
      }
    }

    sock.cast<List<int>>().transform(linhasAte(_maxLinha)).listen((linha) {
      if (autenticado) {
        _receber(linha);
        return;
      }
      prazo.cancel();
      Object? m;
      try {
        m = jsonDecode(linha);
      } catch (_) {}
      if (_ligacao != null || _token.isEmpty || m is! Map || m['tipo'] != 'ola' || !_iguais('${m['token']}', _token)) {
        sock.destroy();
        return;
      }
      autenticado = true;
      _token = ''; // só serve uma vez
      _ligacao = sock;
      // o player entrou: deixa de se aceitar ligações (volta a abrir-se para o próximo player)
      _servidor?.close();
      _servidor = null;
      if (_pendente != null) {
        _enviar(_pendente!);
        _pendente = null;
      }
    }, onDone: fim, onError: (_) => fim(), cancelOnError: true);
  }

  Future<void> _receber(String linha) async {
    final Map m;
    try {
      m = jsonDecode(linha) as Map;
    } catch (_) {
      return;
    }
    if (m['tipo'] != 'fonte') return;
    final i = m['i'] as int? ?? -1;
    final lista = _lista;
    if (lista == null || i < 0 || i >= _canais.length) {
      _enviar({'tipo': 'fonte', 'pedido': m['pedido'], 'erro': 'canal desconhecido'});
      return;
    }
    _aoVer?.call(_canais[i]);
    try {
      final f = await Protocolo.para(lista.conta).fonte(lista.conta, _canais[i]);
      _enviar({'tipo': 'fonte', 'pedido': m['pedido'], 'url': f.url, 'headers': f.headers});
    } catch (e) {
      _enviar({'tipo': 'fonte', 'pedido': m['pedido'], 'erro': e is ErroLista ? e.mensagem : descreverErro(e)});
    }
  }

  /// Fecha o servidor e a ligação (testes).
  @visibleForTesting
  Future<void> fechar() async {
    _ligacao?.destroy();
    _ligacao = null;
    await _servidor?.close();
    _servidor = null;
  }

  void _enviar(Map<String, dynamic> m) => _ligacao?.write('${jsonEncode(m)}\n');
}

/// Linhas de texto (UTF-8) de no máximo `max` bytes: uma linha maior é um erro.
StreamTransformer<List<int>, String> linhasAte(int max) {
  final pendente = BytesBuilder(copy: true);
  return StreamTransformer.fromHandlers(handleData: (bloco, sink) {
    var inicio = 0;
    for (var i = 0; i < bloco.length; i++) {
      if (bloco[i] != 10) continue;
      pendente.add(bloco.sublist(inicio, i));
      sink.add(utf8.decode(pendente.takeBytes(), allowMalformed: true).trimRight());
      inicio = i + 1;
    }
    pendente.add(bloco.sublist(inicio));
    if (pendente.length > max) {
      pendente.clear();
      sink.addError(const FormatException('linha grande demais'));
    }
  });
}

/// Lado da janela do player.
class LigacaoPrincipal {
  LigacaoPrincipal._(this._sock);

  final Socket _sock;
  final _pedidos = <int, Completer<FonteVideo>>{};
  int _proximo = 0;

  /// Recebe {"lista", "canais", "i"} sempre que a principal manda um canal.
  /// Não é broadcast: a principal manda a 1.ª abertura logo a seguir ao "ola", antes de a
  /// janela do player ter lido as preferências e montado a app; um broadcast deitava-a fora
  /// (ninguém a escutar ainda) e a janela ficava para sempre na rodinha. Assim fica guardada
  /// até a app a escutar (só a app a escuta, uma vez).
  final aberturas = StreamController<(String, List<Canal>, int)>();

  /// `aoFechar`: a principal fechou (por omissão a janela do player fecha-se também).
  static Future<LigacaoPrincipal> ligar(int porta, {String token = '', void Function()? aoFechar}) async {
    final fechar = aoFechar ?? () => exit(0);
    final s = await Socket.connect(InternetAddress.loopbackIPv4, porta);
    s.write('${jsonEncode({'tipo': 'ola', 'token': token})}\n');
    final l = LigacaoPrincipal._(s);
    s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(l._receber,
        onDone: fechar, onError: (_) => fechar());
    return l;
  }

  void _receber(String linha) {
    final Map m;
    try {
      m = jsonDecode(linha) as Map;
    } catch (_) {
      return;
    }
    if (m['tipo'] == 'abrir') {
      final canais = [
        for (final c in (m['canais'] as List))
          Canal(id: '${c['id']}', nome: '${c['nome']}', grupo: '${c['grupo']}', numero: numeroCanal(c['num'])),
      ];
      aberturas.add(('${m['lista']}', canais, m['i'] as int));
    } else if (m['tipo'] == 'fonte') {
      final p = _pedidos.remove(m['pedido']);
      if (p == null) return;
      if (m['erro'] != null) {
        p.completeError(ErroLista('${m['erro']}'));
      } else {
        p.complete(FonteVideo('${m['url']}',
            {for (final e in ((m['headers'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'}));
      }
    }
  }

  Future<FonteVideo> fonte(int i) {
    final id = _proximo++;
    final c = _pedidos[id] = Completer<FonteVideo>();
    _sock.write('${jsonEncode({'tipo': 'fonte', 'pedido': id, 'i': i})}\n');
    return c.future.timeout(const Duration(seconds: 30));
  }
}
