/// O guia de uma lista aberta em Ver TV: lê o que está guardado, descarrega o de todos os canais
/// quando é preciso (em segundo plano) e, para um canal sem programação, pede só esse.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'armazem.dart';
import 'fontes.dart';
import 'programa.dart';

enum EstadoGuia {
  /// A descarregar o guia de todos os canais (o guardado, se houver, já está em uso).
  aCarregar,

  /// O guia de todos os canais está pronto (a pesquisa pelo programa funciona).
  pronto,

  /// O servidor não deu o guia de todos os canais: só se pede o do canal escolhido (e a
  /// pesquisa pelo programa não está disponível).
  soPorCanal,
}

/// O que um canal encontrado pelo programa tem a ver com a pesquisa.
typedef EncontradoPeloPrograma = ({Programa programa, bool aDar});

/// A chave do guia de uma lista (o id da lista e a conta: editar a conta começa um guia novo).
String chaveGuia(Lista l) => '${l.id}|${chave(l.conta)}';

/// O guia de uma lista (null = o tipo da lista não tem guia, como as M3U).
ServicoGuia? guiaDaLista(Lista l, {Set<String>? manter}) {
  final f = FonteGuia.para(l.conta);
  if (f == null) return null;
  return ServicoGuia(chave: chaveGuia(l), conta: l.conta, fonte: f, armazem: ArmazemGuia.doAparelho(), manter: manter);
}

int _agoraReal() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class ServicoGuia extends ChangeNotifier {
  ServicoGuia({required this.chave, required this.conta, required this.fonte, Future<ArmazemGuia?>? armazem,
      this.agora = _agoraReal, this.manter})
      : _armazem = armazem ?? Future.value(null);

  final String chave;
  final Conta conta;
  final FonteGuia fonte;
  final Future<ArmazemGuia?> _armazem;

  /// O relógio (segundos UTC; substituível nos testes).
  final int Function() agora;

  /// As chaves dos guias das listas que existem (os outros apagam-se); null = não arruma.
  final Set<String>? manter;

  /// Antes de descarregar o guia de todos os canais (pode ter dezenas de MB): pode? (Poupar
  /// dados móveis.) null = pode sempre.
  Future<bool> Function()? autorizarTodos;

  /// O guia de todos os canais ficou por descarregar para poupar dados móveis.
  bool get poupado => _poupado;
  bool _poupado = false;

  /// Atualiza quando o guia tem mais do que isto…
  static const idadeMaxima = Duration(hours: 4);

  /// …ou quando já só cobre menos do que isto.
  static const coberturaMinima = Duration(hours: 2);

  /// Um guia vazio (o servidor não tinha nada) só se volta a pedir passado isto.
  static const esperaVazio = Duration(hours: 1);

  /// O guia de um canal pedido sozinho vale isto (e uma falha também espera isto).
  static const validadeCanal = Duration(minutes: 10);

  EstadoGuia _estado = EstadoGuia.aCarregar;
  EstadoGuia get estado => _estado;

  /// Muda sempre que alguma coisa muda (a coluna redesenha-se).
  int get versao => _versao;
  int _versao = 0;

  /// Muda só quando a programação muda (a pesquisa pelo programa refaz-se).
  int get versaoDados => _versaoDados;
  int _versaoDados = 0;

  GuiaLista _guia = GuiaLista.vazio();
  List<Canal> _canais = const [];
  final _cancelamento = Cancelamento();
  bool _iniciado = false;
  bool _descarregando = false;
  bool _fechado = false;
  Timer? _verificar;

  /// O guia de cada canal pedido sozinho: quando e os programas.
  final _doCanal = <String, (int, List<Programa>)>{};
  final _aPedir = <String>{};

  /// Os títulos sem acentos (para a pesquisa), feitos uma vez por programa.
  final _titulos = Expando<String>();

  /// Começa (ou, com canais novos depois de «Atualizar», continua) com os canais da lista.
  Future<void> usarCanais(List<Canal> canais) async {
    _canais = canais;
    if (_iniciado) return;
    _iniciado = true;
    final arm = await _armazem;
    if (_fechado) return;
    if (manter != null) unawaited(arm?.arrumar(manter: manter));
    final guardado = await arm?.ler(chave);
    if (_fechado) return;
    if (guardado != null) {
      _guia = guardado;
      _versaoDados++;
      _mudou();
    }
    if (_precisaDeAtualizar()) {
      await _descarregar();
    } else {
      _estado = guardado == null || guardado.vazio ? EstadoGuia.soPorCanal : EstadoGuia.pronto;
      _mudou();
    }
    // com a lista aberta muito tempo, o guia vai-se renovando
    _verificar = Timer.periodic(const Duration(minutes: 15), (_) {
      if (_precisaDeAtualizar()) unawaited(_descarregar());
    });
  }

  bool _precisaDeAtualizar() {
    final idade = Duration(seconds: agora() - _guia.criado.millisecondsSinceEpoch ~/ 1000);
    if (_guia.vazio) return idade > esperaVazio;
    return idade > idadeMaxima || _guia.cobreAte - agora() < coberturaMinima.inSeconds;
  }

  Future<void> _descarregar() async {
    if (_descarregando || _fechado) return;
    _descarregando = true;
    try {
      final pode = autorizarTodos;
      if (pode != null && !await pode()) {
        // fica o guardado (se houver) e pede-se canal a canal; volta a perguntar-se mais tarde
        if (_fechado) return;
        _poupado = true;
        _estado = _guia.vazio ? EstadoGuia.soPorCanal : EstadoGuia.pronto;
        _mudou();
        return;
      }
      if (_fechado) return;
      _poupado = false;
      _estado = EstadoGuia.aCarregar;
      _mudou();
      final anterior = _guia.vazio ? null : _guia;
      final r = await fonte.todos(conta, _canais, anterior: anterior, cancelamento: _cancelamento);
      if (_fechado) return;
      final criado = DateTime.fromMillisecondsSinceEpoch(agora() * 1000);
      if (r.naoMudou && anterior != null) {
        anterior.criado = criado;
      } else {
        _guia = GuiaLista(r.porCanal, criado: criado, etag: r.etag, modificado: r.modificado);
      }
      _estado = _guia.vazio ? EstadoGuia.soPorCanal : EstadoGuia.pronto;
      _versaoDados++;
      final arm = await _armazem;
      if (!_fechado) await arm?.gravar(chave, _guia);
    } on Cancelado {
      return;
    } catch (_) {
      // sem o guia de todos: fica o guardado (se houver) e pede-se canal a canal
      if (_fechado) return;
      _estado = _guia.vazio ? EstadoGuia.soPorCanal : EstadoGuia.pronto;
      // não se volta a tentar logo (o guardado, mesmo velho, conta como "tentado agora")
      if (_guia.vazio) _guia.criado = DateTime.fromMillisecondsSinceEpoch(agora() * 1000);
    } finally {
      _descarregando = false;
    }
    _mudou();
  }

  /// Os programas de um canal que ainda não acabaram (o a dar primeiro).
  List<Programa> programas(Canal c) {
    final t = agora();
    var ps = _guia.porCanal[c.id];
    final sozinho = _doCanal[c.id];
    if ((ps == null || !ps.any((p) => p.fim > t)) && sozinho != null) ps = sozinho.$2;
    return [for (final p in ps ?? const <Programa>[]) if (p.fim > t) p];
  }

  /// O programa a dar e o seguinte de um canal.
  (Programa?, Programa?) agoraESeguinteDe(Canal c) => agoraESeguinte(programas(c), agora());

  /// A pedir o guia só deste canal.
  bool aPedir(Canal c) => _aPedir.contains(c.id);

  /// Pede o guia só deste canal, se não houver nada para ele (nem pedido há pouco).
  Future<void> pedirCanal(Canal c) async {
    if (_fechado || _aPedir.contains(c.id) || programas(c).isNotEmpty) return;
    final antes = _doCanal[c.id];
    if (antes != null && agora() - antes.$1 < validadeCanal.inSeconds) return;
    _aPedir.add(c.id);
    _mudou();
    try {
      final ps = await fonte.doCanal(conta, c, cancelamento: _cancelamento);
      _doCanal[c.id] = (agora(), ps);
      if (ps.isNotEmpty) _versaoDados++;
    } on Cancelado {
      return;
    } catch (_) {
      _doCanal[c.id] = (agora(), const []);
    } finally {
      _aPedir.remove(c.id);
    }
    _mudou();
  }

  /// A pesquisa pelo programa funciona (há o guia de todos os canais).
  bool get pesquisaDisponivel => !_guia.vazio;

  /// Os canais (por id) com o programa a dar ou o seguinte cujo título tem `q` (já sem acentos).
  Map<String, EncontradoPeloPrograma> procurar(String q) {
    if (q.isEmpty) return const {};
    final t = agora();
    final r = <String, EncontradoPeloPrograma>{};
    void ver(String id, List<Programa> ps) {
      final (atual, seguinte) = agoraESeguinte(ps, t);
      if (atual != null && _titulo(atual).contains(q)) {
        r[id] = (programa: atual, aDar: true);
      } else if (seguinte != null && _titulo(seguinte).contains(q)) {
        r[id] = (programa: seguinte, aDar: false);
      }
    }

    for (final e in _guia.porCanal.entries) {
      ver(e.key, e.value);
    }
    for (final e in _doCanal.entries) {
      if (!r.containsKey(e.key)) ver(e.key, e.value.$2);
    }
    return r;
  }

  String _titulo(Programa p) => _titulos[p] ??= semAcentos(p.titulo);

  void _mudou() {
    if (_fechado) return;
    _versao++;
    notifyListeners();
  }

  @override
  void dispose() {
    _fechado = true;
    _verificar?.cancel();
    _cancelamento.cancelar();
    super.dispose();
  }
}
