/// Windows: o player corre numa janela própria — o mesmo .exe lançado com `--player <porta>`.
/// A janela principal abre um socket em 127.0.0.1 e manda-lhe linhas JSON:
///   principal → player: {"tipo":"abrir","lista":"001X","canais":[...],"i":3}
///   player → principal: {"tipo":"fonte","pedido":7,"i":4}
///   principal → player: {"tipo":"fonte","pedido":7,"url":"…","headers":{…}} ou {"…","erro":"…"}
/// Assim o link do canal (que no Stalker precisa da sessão do portal) é sempre pedido pela
/// janela principal, e trocar de canal na principal muda o canal na janela do player.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../dados/biblioteca.dart';
import '../modelo/canal.dart';
import '../protocolos/protocolo.dart';
import '../rede/http.dart';

/// Lado da janela principal.
class JanelaPlayer {
  JanelaPlayer._();
  static final instancia = JanelaPlayer._();

  ServerSocket? _servidor;
  Socket? _ligacao;
  Process? _processo;
  Lista? _lista;
  List<Canal> _canais = const [];
  Map<String, dynamic>? _pendente;

  /// Mostra `canais[i]` na janela do player (abre-a se não estiver aberta).
  Future<void> mostrar(Lista lista, List<Canal> canais, int i) async {
    _lista = lista;
    _canais = canais;
    final msg = {
      'tipo': 'abrir', 'lista': lista.nomeMostrado, 'i': i,
      'canais': [for (final c in canais) {'id': c.id, 'nome': c.nome, 'grupo': c.grupo}],
    };
    if (_ligacao != null) {
      _enviar(msg);
      return;
    }
    _pendente = msg;
    if (_processo != null) return; // a abrir: a mensagem vai quando ligar
    final srv = _servidor ??= await _abrirServidor();
    _processo = await Process.start(Platform.resolvedExecutable, ['--player', '${srv.port}'],
        mode: ProcessStartMode.detached);
    // se a janela não ligar em 20 s, desiste-se (o próximo clique tenta de novo)
    Timer(const Duration(seconds: 20), () {
      if (_ligacao == null) _processo = null;
    });
  }

  Future<ServerSocket> _abrirServidor() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((sock) {
      _ligacao?.destroy();
      _ligacao = sock;
      if (_pendente != null) {
        _enviar(_pendente!);
        _pendente = null;
      }
      sock.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
        _receber,
        onDone: () {
          if (identical(_ligacao, sock)) {
            _ligacao = null;
            _processo = null;
          }
        },
        onError: (_) {},
      );
    });
    return s;
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
    try {
      final f = await Protocolo.para(lista.conta).fonte(lista.conta, _canais[i]);
      _enviar({'tipo': 'fonte', 'pedido': m['pedido'], 'url': f.url, 'headers': f.headers});
    } catch (e) {
      _enviar({'tipo': 'fonte', 'pedido': m['pedido'], 'erro': e is ErroLista ? e.mensagem : descreverErro(e)});
    }
  }

  void _enviar(Map<String, dynamic> m) => _ligacao?.write('${jsonEncode(m)}\n');
}

/// Lado da janela do player.
class LigacaoPrincipal {
  LigacaoPrincipal._(this._sock);

  final Socket _sock;
  final _pedidos = <int, Completer<FonteVideo>>{};
  int _proximo = 0;

  /// Recebe {"lista", "canais", "i"} sempre que a principal manda um canal.
  final aberturas = StreamController<(String, List<Canal>, int)>.broadcast();

  static Future<LigacaoPrincipal> ligar(int porta) async {
    final s = await Socket.connect(InternetAddress.loopbackIPv4, porta);
    final l = LigacaoPrincipal._(s);
    s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(l._receber,
        onDone: () => exit(0), onError: (_) => exit(0)); // a principal fechou: fecha-se também
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
          Canal(id: '${c['id']}', nome: '${c['nome']}', grupo: '${c['grupo']}'),
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
