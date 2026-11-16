/// Abrir uma lista (grupos + canais) e obter o link de um canal, para os três tipos de lista.
library;

import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'm3u_remoto.dart';
import 'stalker.dart';
import 'xtream.dart';

/// Progresso legível ("a pedir os canais · página 3/12").
typedef Aviso = void Function(String texto);

abstract class Protocolo {
  Future<ConteudoLista> abrir(Conta conta, {Cancelamento? cancelamento, Aviso? aviso});
  Future<FonteVideo> fonte(Conta conta, Canal canal, {Cancelamento? cancelamento});

  static final _stalker = Stalker();
  static final _xtream = Xtream();
  static final _m3u = M3uRemoto();

  static Protocolo para(Conta c) => switch (c.tipo) {
        Tipo.stalker => _stalker,
        Tipo.xtream => _xtream,
        Tipo.m3u => _m3u,
      };
}

class ErroLista implements Exception {
  ErroLista(this.mensagem);
  final String mensagem;
  @override
  String toString() => mensagem;
}
