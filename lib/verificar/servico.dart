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
/// - cada volta de uma conta tem um limite de tempo.
class ServicoVerificacao extends ChangeNotifier {
  ServicoVerificacao(this.biblioteca,
      {ColecaoListas? colecao, Verificador? verificador, this.workers = 4, RitmoHost? ritmo,
      this.preferencias})
      : colecao = colecao ?? biblioteca,
        verificador = verificador ?? Verificador(),
        ritmo = ritmo ?? RitmoHost();

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

  /// O tempo limite de cada canal, das Definições (lido a cada volta: mudar vale logo).
  Duration get _timeout => Duration(seconds: (preferencias ?? Preferencias.atual).timeoutVerificacao);

  /// id da lista -> o passo em curso ("a pedir os canais", "na fila"...).
  final passos = <String, String>{};
  final _fila = <(Lista, Completer<void>)>[];
  final _reteste = Queue<(Lista, Completer<void>, ResultadoVerificacao)>();
  final _macsOcupados = <String>{};
  final _hostsOcupados = <String, int>{};
  int _aCorrer = 0;
  bool _aRetestar = false;
  Cancelamento _cancelamento = Cancelamento();
  int feitas = 0, total = 0;

  bool aVerificar(String id) => passos.containsKey(id);
  bool get ocupado => passos.isNotEmpty;

  Future<void> verificar(Lista l) {
    if (passos.containsKey(l.id)) return Future.value();
    final c = Completer<void>();
    passos[l.id] = 'na fila';
    total++;
    _fila.add((l, c));
    notifyListeners();
    _servir();
    return c.future;
  }

  Future<void> verificarVarias(Iterable<Lista> ls) => Future.wait([for (final l in ls) verificar(l)]);

  /// Pára tudo: as que estão a meio ficam com o resultado que tinham (as que esperavam a
  /// 2.ª volta ficam com o da 1.ª).
  void parar() {
    _cancelamento.cancelar();
    _cancelamento = Cancelamento();
    for (final (l, c) in _fila) {
      passos.remove(l.id);
      c.complete();
    }
    _fila.clear();
    for (final (l, c, _) in _reteste) {
      passos.remove(l.id);
      c.complete();
    }
    _reteste.clear();
    if (passos.isEmpty) feitas = total = 0;
    notifyListeners();
  }

  static String _mac(Conta c) => c.tipo == Tipo.stalker ? c.mac.trim().toUpperCase() : '';
  static String _host(Conta c) => hostDe(c.endereco).toLowerCase();

  void _ocupar(Conta c) {
    final m = _mac(c);
    if (m.isNotEmpty) _macsOcupados.add(m);
    _hostsOcupados.update(_host(c), (n) => n + 1, ifAbsent: () => 1);
  }

  void _libertar(Conta c) {
    _macsOcupados.remove(_mac(c));
    final h = _host(c);
    final n = (_hostsOcupados[h] ?? 1) - 1;
    if (n <= 0) {
      _hostsOcupados.remove(h);
    } else {
      _hostsOcupados[h] = n;
    }
  }

  /// A próxima da fila cujo MAC não esteja em uso; entre essas, uma de um servidor livre.
  int? _proxima() {
    int? primeira;
    for (var i = 0; i < _fila.length; i++) {
      final c = _fila[i].$1.conta;
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
      final (l, c) = _fila.removeAt(i);
      _aCorrer++;
      _ocupar(l.conta);
      final can = _cancelamento;
      _primeiraVolta(l, can).then((r) {
        _aCorrer--;
        _libertar(l.conta);
        if (r != null && r.estado == EstadoV.inconclusivo && !can.cancelado) {
          passos[l.id] = 'inconclusiva: à espera da 2.ª volta';
          _reteste.add((l, c, r));
        } else {
          _concluir(l, c);
        }
        notifyListeners();
        _servir();
      });
    }
    // a 2.ª volta só quando a 1.ª acabou, e uma de cada vez
    if (_aCorrer == 0 && _fila.isEmpty && !_aRetestar && _reteste.isNotEmpty) {
      final (l, c, r1) = _reteste.removeFirst();
      _aRetestar = true;
      _ocupar(l.conta);
      _segundaVolta(l, r1, _cancelamento).whenComplete(() {
        _aRetestar = false;
        _libertar(l.conta);
        _concluir(l, c);
        notifyListeners();
        _servir();
      });
    }
  }

  void _concluir(Lista l, Completer<void> c) {
    passos.remove(l.id);
    feitas++;
    if (passos.isEmpty) feitas = total = 0;
    if (!c.isCompleted) c.complete();
  }

  void Function(String) _aviso(Lista l) => (t) {
        if (passos.containsKey(l.id)) {
          passos[l.id] = t;
          notifyListeners();
        }
      };

  Future<ResultadoVerificacao> _umaVolta(Lista l, Cancelamento can, Duration timeout) => runZoned(
      () => verificador.verificarComLimite(l.conta, biblioteca.canaisTeste,
          timeout: timeout, cancelamento: can, aviso: _aviso(l)),
      zoneValues: {ritmoZona: ritmo});

  /// O resultado da 1.ª volta (já guardado), ou null se foi parada.
  Future<ResultadoVerificacao?> _primeiraVolta(Lista l, Cancelamento can) async {
    passos[l.id] = 'a começar';
    notifyListeners();
    try {
      final r = await _umaVolta(l, can, _timeout);
      await colecao.registarVerificacao(l.id, paraUltima(r));
      return r;
    } on Cancelado {
      return null; // parada: fica o resultado anterior
    } catch (e) {
      await colecao.registarVerificacao(
          l.id, paraUltima(ResultadoVerificacao(EstadoV.inconclusivo, 'falha: ${descreverErro(e)}')));
      return null;
    }
  }

  Future<void> _segundaVolta(Lista l, ResultadoVerificacao r1, Cancelamento can) async {
    passos[l.id] = 'inconclusiva: a testar outra vez';
    notifyListeners();
    try {
      await esperarCancelavel(verificador.pausaReteste, can);
      final r2 = await _umaVolta(l, can, _timeout * 2);
      // o reteste pode não chegar à data
      final r = r2.validade.isEmpty && r1.validade.isNotEmpty ? r2.com(validade: r1.validade) : r2;
      await colecao.registarVerificacao(l.id, paraUltima(r));
    } on Cancelado {
      // parada: fica o resultado da 1.ª volta
    } catch (_) {
      // fica o resultado da 1.ª volta
    }
  }
}
