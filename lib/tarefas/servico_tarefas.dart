import 'dart:async';

import 'package:flutter/foundation.dart';

import '../rede/http.dart' show Cancelado;
import 'segredos.dart';

enum EstadoTarefa { aDecorrer, terminada, falhou, cancelada }

/// Uma tarefa longa (importar, pesquisar, enviar, exportar) que corre fora dos ecrãs.
class Tarefa {
  final String id;
  final String titulo;
  EstadoTarefa estado = EstadoTarefa.aDecorrer;
  double? progresso;
  String detalhe = '';
  String? resultado;
  final DateTime inicio;
  DateTime? fim;
  final Future<void> Function()? repetir;

  /// Se o "Parar" tem efeito. Falso no trabalho que não se pode interromper (enviar para o Player,
  /// gravar um ficheiro): o painel não mostra "Parar" e o [ServicoTarefas.cancelar] é ignorado.
  bool cancelavel;

  /// Ação oferecida na mensagem de fim (ex.: "Ir para Ver TV").
  final String? rotuloAcao;
  final VoidCallback? aoAcao;

  Tarefa({
    required this.id,
    required this.titulo,
    required this.inicio,
    this.repetir,
    this.rotuloAcao,
    this.aoAcao,
    this.cancelavel = true,
  });
}

/// Passado ao trabalho: reporta o progresso e deixa ver se foi cancelado. O trabalho que pára a
/// meio lança [Cancelado] (a tarefa acaba `cancelada`).
class Progresso {
  final void Function(double? fracao, String detalhe) _aoReportar;
  final VoidCallback? _aoFixar;
  bool _cancelado = false;
  Progresso(this._aoReportar, [this._aoFixar]);

  void call(double? fracao, String detalhe) => _aoReportar(fracao, detalhe);
  bool get cancelado => _cancelado;

  /// Daqui em diante o trabalho já não se pode parar (ex.: começou a gravar): o "Parar" sai.
  void naoCancelavel() => _aoFixar?.call();
}

/// Corre o trabalho longo sem prender nenhum ecrã: a UI só observa.
class ServicoTarefas extends ChangeNotifier {
  static const _maxRecentes = 10;

  final _emCurso = <Tarefa>[];
  final _recentes = <Tarefa>[]; // mais recente primeiro
  final _progressos = <String, Progresso>{};
  final _acabadas = StreamController<Tarefa>.broadcast();
  int _contador = 0;
  bool _fechado = false;

  List<Tarefa> get emCurso => List.unmodifiable(_emCurso);
  List<Tarefa> get recentes => List.unmodifiable(_recentes);
  Stream<Tarefa> get acabadas => _acabadas.stream;

  /// Arranca já o trabalho (sem esperar) e devolve a tarefa a decorrer.
  Tarefa iniciar(
    String titulo,
    Future<String> Function(Progresso p) trabalho, {
    Future<void> Function()? repetir,
    String? rotuloAcao,
    VoidCallback? aoAcao,
    bool cancelavel = true,
  }) {
    final t = Tarefa(
      id: '${++_contador}',
      titulo: titulo,
      inicio: DateTime.now(),
      repetir: repetir,
      rotuloAcao: rotuloAcao,
      aoAcao: aoAcao,
      cancelavel: cancelavel,
    );
    final p = Progresso((fracao, detalhe) {
      if (t.estado != EstadoTarefa.aDecorrer) return;
      t.progresso = fracao;
      t.detalhe = mascararSegredos(detalhe);
      _avisar();
    }, () {
      if (!t.cancelavel || t.estado != EstadoTarefa.aDecorrer) return;
      t.cancelavel = false;
      _avisar();
    });
    _progressos[t.id] = p;
    _emCurso.add(t);
    _avisar();
    unawaited(_correr(t, p, trabalho));
    return t;
  }

  Future<void> _correr(Tarefa t, Progresso p, Future<String> Function(Progresso) trabalho) async {
    EstadoTarefa fim;
    String resultado;
    try {
      resultado = await trabalho(p);
      fim = EstadoTarefa.terminada;
    } on Cancelado {
      resultado = 'Parada antes de acabar.';
      fim = EstadoTarefa.cancelada;
    } catch (e) {
      resultado = '$e';
      fim = EstadoTarefa.falhou;
    }
    if (p.cancelado) fim = EstadoTarefa.cancelada;
    t.estado = fim;
    t.resultado = mascararSegredos(resultado);
    t.fim = DateTime.now();
    _progressos.remove(t.id);
    _emCurso.remove(t);
    _recentes.insert(0, t);
    if (_recentes.length > _maxRecentes) _recentes.removeRange(_maxRecentes, _recentes.length);
    if (_fechado) return;
    _acabadas.add(t);
    notifyListeners();
  }

  void cancelar(String id) {
    final p = _progressos[id];
    if (p == null || p._cancelado) return;
    if (!_emCurso.any((t) => t.id == id && t.cancelavel)) return;
    p._cancelado = true;
    _avisar();
  }

  void _avisar() {
    if (!_fechado) notifyListeners();
  }

  @override
  void dispose() {
    _fechado = true;
    for (final p in _progressos.values) {
      p._cancelado = true;
    }
    _acabadas.close();
    super.dispose();
  }
}
