import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart';
import '../dados/preferencias.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'estado.dart';
import 'verificador.dart';

/// Corre verificações e guarda os resultados na coleção verificada, como a `Analise` do Python:
/// - 1.ª volta com no máximo `workers` ao mesmo tempo, um MAC de cada vez, preferindo
///   servidores que não estejam já a ser testados, e um pedido de cada vez por servidor;
/// - as inconclusivas voltam a ser testadas (com o dobro do tempo) depois da 1.ª volta,
///   uma de cada vez, com uma pausa antes de cada uma;
/// - cada volta de uma conta tem um limite de tempo;
/// - pode-se juntar listas à fila a meio e cancelar uma só sem parar as outras.
class ServicoVerificacao extends ChangeNotifier {
  ServicoVerificacao(this.biblioteca,
      {ColecaoListas? colecao, Verificador? verificador, this.workers = 4, RitmoHost? ritmo,
      this.preferencias, DateTime Function()? agora})
      : colecao = colecao ?? biblioteca,
        verificador = verificador ?? Verificador(),
        ritmo = ritmo ?? RitmoHost(),
        _agora = agora ?? DateTime.now;

  /// Dá os canais de teste.
  final Biblioteca biblioteca;

  /// Onde se gravam os resultados (o Gestor na app; a biblioteca por omissão).
  final ColecaoListas colecao;
  final Verificador verificador;
  final int workers;

  /// Um pedido de cada vez por servidor, partilhado por todas as verificações.
  final RitmoHost ritmo;

  /// As definições (por omissão as da app).
  final Preferencias? preferencias;

  /// O relógio da estimativa (trocável nos testes).
  final DateTime Function() _agora;

  /// O tempo limite de cada canal, das Definições (lido a cada volta: mudar vale logo).
  Duration get _timeout => Duration(seconds: (preferencias ?? Preferencias.atual).timeoutVerificacao);

  /// id da lista -> o passo em curso ("a pedir os canais", "na fila"...).
  final passos = <String, String>{};
  final _fila = <_Tarefa>[];
  final _reteste = Queue<_Tarefa>();
  final _emCurso = <_Tarefa>{};
  final _macsOcupados = <String>{};
  final _hostsOcupados = <String, int>{};
  int _aCorrer = 0;
  bool _aRetestar = false;
  Cancelamento _cancelamento = Cancelamento();
  int feitas = 0, total = 0;

  /// Quando começou esta ronda e quantas 1.as voltas já terminaram nela (para a estimativa).
  DateTime? _inicioRonda;
  int _nTerminadas = 0;

  bool aVerificar(String id) => passos.containsKey(id);
  bool get ocupado => passos.isNotEmpty;

  /// O tempo que falta, ao ritmo real da ronda: (tempo desde que a ronda começou ÷ 1.as
  /// voltas terminadas nela) × as que faltam acabar (`null` antes da primeira). Assim conta o
  /// paralelismo dos `workers`; as 2.as voltas não contam como terminadas.
  Duration? get estimativaRestante {
    final inicio = _inicioRonda;
    if (inicio == null || _nTerminadas == 0) return null;
    final porFazer = total - feitas;
    return _agora().difference(inicio) ~/ _nTerminadas * (porFazer < 0 ? 0 : porFazer);
  }

  Future<void> verificar(Lista l) {
    if (passos.containsKey(l.id)) return Future.value();
    final t = _Tarefa(l);
    if (passos.isEmpty) _inicioRonda = _agora();
    passos[l.id] = 'na fila';
    total++;
    _fila.add(t);
    notifyListeners();
    _servir();
    return t.acabou.future;
  }

  /// Pode ser chamado com o serviço ocupado: as novas juntam-se à fila e `total` cresce.
  Future<void> verificarVarias(Iterable<Lista> ls) => Future.wait([for (final l in ls) verificar(l)]);

  /// Pára tudo: as que estão a meio ficam com o resultado que tinham (as que esperavam a
  /// 2.ª volta ficam com o da 1.ª).
  void parar() {
    _cancelamento.cancelar();
    _cancelamento = Cancelamento();
    for (final t in _fila) {
      passos.remove(t.id);
      t.acabar();
    }
    _fila.clear();
    for (final t in _reteste) {
      passos.remove(t.id);
      t.acabar();
    }
    _reteste.clear();
    if (passos.isEmpty) _recomecarContas();
    notifyListeners();
  }

  /// Cancela só esta lista: sai da fila (ou da espera da 2.ª volta) ou, se está a correr, os
  /// pedidos dela param, o MAC e o servidor ficam logo livres para as outras e o resultado
  /// não é gravado (fica o que tinha). Sai de `total`; as outras continuam. Uma que já está a
  /// gravar o resultado já não se cancela (acaba normalmente).
  void cancelar(String id) {
    _Tarefa? t;
    final i = _fila.indexWhere((t) => t.id == id);
    if (i >= 0) {
      t = _fila.removeAt(i);
    } else {
      t = _reteste.where((t) => t.id == id).firstOrNull;
      if (t != null) {
        _reteste.remove(t);
      } else {
        t = _emCurso.where((t) => t.id == id && !t.cancelada).firstOrNull;
        if (t == null || t.aGravar) return;
        t.cancelada = true;
        t.cancelamento?.cancelar();
        _largar(t);
      }
    }
    t.cancelada = true;
    passos.remove(id);
    total--;
    if (passos.isEmpty) _recomecarContas();
    t.acabar();
    notifyListeners();
    _servir();
  }

  void _recomecarContas() {
    feitas = total = 0;
    _inicioRonda = null;
    _nTerminadas = 0;
  }

  static String _mac(Conta c) => c.tipo == Tipo.stalker ? c.mac.trim().toUpperCase() : '';
  static String _host(Conta c) => hostDe(c.endereco).toLowerCase();

  /// Ocupa o MAC, o servidor e a vaga (da 1.ª volta ou do reteste) desta tarefa.
  void _ocupar(_Tarefa t, {required bool segunda}) {
    final c = t.lista.conta;
    final m = _mac(c);
    if (m.isNotEmpty) _macsOcupados.add(m);
    _hostsOcupados.update(_host(c), (n) => n + 1, ifAbsent: () => 1);
    if (segunda) {
      _aRetestar = true;
    } else {
      _aCorrer++;
    }
    t
      ..segunda = segunda
      ..largada = false
      ..aGravar = false
      ..cancelamento = _cancelamento.filho();
    _emCurso.add(t);
  }

  /// Liberta o que [_ocupar] ocupou, uma só vez por volta (ao cancelar e quando a volta sai).
  /// Só mexe nas contas deste serviço: a vez de cada servidor no [RitmoHost] partilhado é
  /// devolvida pelo próprio pedido, na ordem em que chegou.
  void _largar(_Tarefa t) {
    if (t.largada) return;
    t.largada = true;
    _emCurso.remove(t);
    final c = t.lista.conta;
    _macsOcupados.remove(_mac(c));
    final h = _host(c);
    final n = (_hostsOcupados[h] ?? 1) - 1;
    if (n <= 0) {
      _hostsOcupados.remove(h);
    } else {
      _hostsOcupados[h] = n;
    }
    if (t.segunda) {
      _aRetestar = false;
    } else {
      _aCorrer--;
    }
  }

  /// A próxima da fila cujo MAC não esteja em uso; entre essas, uma de um servidor livre.
  int? _proxima() {
    int? primeira;
    for (var i = 0; i < _fila.length; i++) {
      final c = _fila[i].lista.conta;
      final m = _mac(c);
      if (m.isNotEmpty && _macsOcupados.contains(m)) continue;
      if ((_hostsOcupados[_host(c)] ?? 0) == 0) return i;
      primeira ??= i;
    }
    return primeira;
  }

  void _servir() {
    while (_aCorrer < workers) {
      final i = _proxima();
      if (i == null) break;
      final t = _fila.removeAt(i);
      _ocupar(t, segunda: false);
      _primeiraVolta(t).then((r) {
        _largar(t);
        if (t.cancelada) {
          // já saiu das contas ao cancelar
        } else if (r != null && r.estado == EstadoV.inconclusivo && !t.cancelamento!.cancelado) {
          passos[t.id] = 'inconclusiva: à espera da 2.ª volta';
          t.r1 = r;
          _reteste.add(t);
        } else {
          _concluir(t);
        }
        notifyListeners();
        _servir();
      });
    }
    // a 2.ª volta só quando a 1.ª acabou, e uma de cada vez
    if (_aCorrer == 0 && _fila.isEmpty && !_aRetestar && _reteste.isNotEmpty) {
      final t = _reteste.removeFirst();
      _ocupar(t, segunda: true);
      _segundaVolta(t).whenComplete(() {
        _largar(t);
        if (!t.cancelada) _concluir(t);
        notifyListeners();
        _servir();
      });
    }
  }

  void _concluir(_Tarefa t) {
    passos.remove(t.id);
    feitas++;
    if (passos.isEmpty) _recomecarContas();
    t.acabar();
  }

  void Function(String) _aviso(_Tarefa t) => (texto) {
        if (!t.cancelada && passos.containsKey(t.id)) {
          passos[t.id] = texto;
          notifyListeners();
        }
      };

  Future<ResultadoVerificacao> _umaVolta(_Tarefa t, Duration timeout) => runZoned(
      () => verificador.verificarComLimite(t.lista.conta, biblioteca.canaisTeste,
          timeout: timeout, cancelamento: t.cancelamento, aviso: _aviso(t)),
      zoneValues: {ritmoZona: ritmo});

  /// Grava o resultado da volta; enquanto grava, `cancelar` ignora-a. Devolve false se a
  /// gravação falhou (a lista acaba na mesma, com o resultado que tinha).
  Future<bool> _gravar(_Tarefa t, ResultadoVerificacao r) async {
    t.aGravar = true;
    try {
      await colecao.registarVerificacao(t.id, paraUltima(r));
      return true;
    } catch (_) {
      return false;
    } finally {
      t.aGravar = false;
    }
  }

  /// O resultado da 1.ª volta (já guardado), ou null se foi parada, cancelada, falhou ou não
  /// se conseguiu gravar. Nunca lança: a lista sai sempre de `_emCurso`.
  Future<ResultadoVerificacao?> _primeiraVolta(_Tarefa t) async {
    final can = t.cancelamento!;
    passos[t.id] = 'a começar';
    notifyListeners();
    ResultadoVerificacao r;
    var falhou = false;
    try {
      r = await _umaVolta(t, _timeout);
    } on Cancelado {
      return null; // parada: fica o resultado anterior
    } catch (e) {
      r = ResultadoVerificacao(EstadoV.inconclusivo, 'falha: ${descreverErro(e)}');
      falhou = true;
    }
    if (can.cancelado) return null; // parada ou cancelada: fica o resultado anterior
    _nTerminadas++;
    final gravou = await _gravar(t, r);
    return gravou && !falhou ? r : null;
  }

  Future<void> _segundaVolta(_Tarefa t) async {
    final can = t.cancelamento!;
    final r1 = t.r1!;
    passos[t.id] = 'inconclusiva: a testar outra vez';
    notifyListeners();
    try {
      await esperarCancelavel(verificador.pausaReteste, can);
      final r2 = await _umaVolta(t, _timeout * 2);
      if (can.cancelado) return; // parada ou cancelada: fica o resultado da 1.ª volta
      // o reteste pode não chegar à data
      final r = r2.validade.isEmpty && r1.validade.isNotEmpty ? r2.com(validade: r1.validade) : r2;
      await _gravar(t, r); // se falhar, fica o resultado da 1.ª volta
    } on Cancelado {
      // parada: fica o resultado da 1.ª volta
    } catch (_) {
      // fica o resultado da 1.ª volta
    }
  }
}

/// Uma lista pedida ao serviço, da fila até acabar.
class _Tarefa {
  _Tarefa(this.lista);
  final Lista lista;
  final acabou = Completer<void>();

  /// O cancelamento da volta em curso (filho do do serviço: `parar()` cancela-o também).
  Cancelamento? cancelamento;
  ResultadoVerificacao? r1;
  bool segunda = false, largada = true, cancelada = false;

  /// A gravar o resultado da volta: `cancelar` ignora-a (o resultado seria gravado na mesma).
  bool aGravar = false;

  String get id => lista.id;

  void acabar() {
    if (!acabou.isCompleted) acabou.complete();
  }
}
