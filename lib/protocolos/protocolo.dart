/// Abrir uma lista (grupos + canais) e obter o link de um canal, para os três tipos de lista.
library;

import '../dados/preferencias.dart';
import '../modelo/canal.dart';
import '../modelo/conta.dart';
import '../rede/http.dart';
import 'm3u_remoto.dart';
import 'stalker.dart';
import 'xtream.dart';

/// O user-agent dos pedidos M3U e Xtream: o das Definições ou, sem ele, o do VLC. O Stalker
/// mantém sempre o da box MAG.
String uaListas() {
  final ua = Preferencias.atual.userAgent;
  return ua.isEmpty ? uaVlc : ua;
}

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

class ErroLista implements Exception, ErroLegivel {
  ErroLista(this.mensagem, {this.definitivo = false, this.fixo = false});
  @override
  final String mensagem;

  /// Prova de que a lista não funciona (conta recusada, expirada, portal inexistente).
  final bool definitivo;

  /// Não prova nada, mas também não muda ao repetir daqui a minutos (o servidor não é um
  /// painel Xtream, o endereço não devolve uma lista): a 2.ª volta não vale a pena.
  final bool fixo;
  @override
  String toString() => mensagem;
}
