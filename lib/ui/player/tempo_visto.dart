import 'dart:async';

import '../../dados/estatisticas.dart';
import '../../dados/preferencias.dart';
import '../../modelo/canal.dart';

/// O [PlayerCanais.aoTempoVisto] de uma lista: soma o tempo às estatísticas (se a opção
/// «Contar o tempo de visualização» estiver ligada) e grava no máximo uma vez por minuto (o
/// resto grava-se ao sair do player: [guardarTempoVisto]).
void Function(Canal canal, Duration tempo) contadorDeTempo(String listaId, String listaNome,
    {Estatisticas? estatisticas, Preferencias? preferencias, DateTime Function()? agora}) {
  DateTime? gravado;
  return (canal, tempo) {
    if (!(preferencias ?? Preferencias.atual).contarTempo || listaId.isEmpty) return;
    final e = estatisticas ?? Estatisticas.atual;
    final t = (agora ?? DateTime.now)();
    e.somar(listaId, listaNome, canal, tempo, quando: t);
    final antes = gravado;
    if (antes == null || t.difference(antes) >= const Duration(minutes: 1)) {
      gravado = t;
      unawaited(e.guardar(agora: t));
    }
  };
}

/// Ao sair do player: grava o que ainda não se gravou.
Future<void> guardarTempoVisto() => Estatisticas.atual.guardar();
