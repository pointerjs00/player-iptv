import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../dados/biblioteca.dart';
import '../rede/http.dart';
import 'estado.dart';
import 'verificador.dart';

/// Corre verificações (no máximo `workers` ao mesmo tempo), guarda os resultados na
/// biblioteca e diz o que cada uma está a fazer.
class ServicoVerificacao extends ChangeNotifier {
  ServicoVerificacao(this.biblioteca, {Verificador? verificador, this.workers = 4})
      : verificador = verificador ?? Verificador();

  final Biblioteca biblioteca;
  final Verificador verificador;
  final int workers;

  /// id da lista -> o passo em curso ("a pedir os canais", "na fila"...).
  final passos = <String, String>{};
  final _fila = Queue<(Lista, Completer<void>)>();
  int _aCorrer = 0;
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

  /// Pára tudo: as que estão a meio ficam com o resultado que tinham.
  void parar() {
    _cancelamento.cancelar();
    _cancelamento = Cancelamento();
    for (final (l, c) in _fila) {
      passos.remove(l.id);
      c.complete();
    }
    _fila.clear();
    notifyListeners();
  }

  void _servir() {
    while (_aCorrer < workers && _fila.isNotEmpty) {
      final (l, c) = _fila.removeFirst();
      _aCorrer++;
      _correr(l, _cancelamento).whenComplete(() {
        _aCorrer--;
        passos.remove(l.id);
        feitas++;
        if (passos.isEmpty) feitas = total = 0;
        c.complete();
        notifyListeners();
        _servir();
      });
    }
  }

  Future<void> _correr(Lista l, Cancelamento can) async {
    passos[l.id] = 'a começar';
    notifyListeners();
    try {
      final r = await verificador.verificar(l.conta, biblioteca.canaisTeste, cancelamento: can,
          aviso: (t) {
        if (passos.containsKey(l.id)) {
          passos[l.id] = t;
          notifyListeners();
        }
      });
      await biblioteca.registarVerificacao(l.id, paraUltima(r));
    } on Cancelado {
      // parada: fica o resultado anterior
    } catch (e) {
      await biblioteca.registarVerificacao(l.id, paraUltima(ResultadoVerificacao(EstadoV.inconclusivo, 'falha: $e')));
    }
  }
}
