import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../desporto/onde_ver.dart';
import '../../direto/sessao_direto.dart';
import '../../janelas/janela_player.dart';
import '../../modelo/canal.dart';
import '../../modelo/conta.dart';
import '../../protocolos/protocolo.dart';
import 'player_canais.dart';
import 'tempo_visto.dart';
import '../design/mensagens.dart';

/// Abre o canal: no Windows numa janela separada; no Android em ecrã inteiro. No Android
/// devolve, ao sair do player, o índice do canal que estava a tocar (pode ter mudado).
/// `aoVer` é chamado com cada canal que o player abre (o primeiro e os do zapping).
Future<int?> abrirCanal(BuildContext context, Lista lista, List<Canal> canais, int i,
    {ValueChanged<Canal>? aoVer}) async {
  if (Platform.isWindows) {
    final dizer = mensageiroDe(context);
    void avisar(String m) => dizer(m);
    try {
      await JanelaPlayer.instancia.mostrar(lista, canais, i, aoFalhar: avisar, aoVer: aoVer);
    } on ErroLista catch (e) {
      avisar(e.mensagem);
    }
    return null;
  }
  final atual = ValueNotifier(i);
  // o tempo visto (as estatísticas), por esta lista
  final tempoVisto = contadorDeTempo(lista.id, lista.nomeMostrado);
  final conta = lista.conta;
  await _mostrarPagina(
    context,
    (aoSair) => PlayerCanais(
      canais: canais,
      indice: i,
      nomeLista: lista.nomeMostrado,
      resolver: (c, {continuar = false}) {
        // um corte do servidor não é ver o canal outra vez
        if (!continuar) aoVer?.call(c);
        return Protocolo.para(conta).fonte(conta, c);
      },
      aoSair: aoSair,
      aoMudarCanal: (i) => atual.value = i,
      // o direto gravado (2 GB na cache da app); a preferência vem depois
      criarSessao: criarSessaoDireto,
      aoTempoVisto: tempoVisto,
    ),
  );
  return atual.value;
}

/// Modo «Jogo»: abre as fontes de um canal (de várias listas), pela ordem dada. Com
/// `trocaAutomatica`, uma fonte que falha passa à seguinte. `aoFuncionar` recebe a fonte que deu
/// imagem (para «funcionou da última vez»); `aoVer`, a fonte de cada canal que o player abre.
Future<void> abrirFontes(BuildContext context, List<FonteCanal> fontes,
    {bool trocaAutomatica = true, ValueChanged<FonteCanal>? aoFuncionar, ValueChanged<FonteCanal>? aoVer}) async {
  if (fontes.isEmpty) return;
  if (Platform.isWindows) {
    final dizer = mensageiroDe(context);
    void avisar(String m) => dizer(m);
    try {
      await JanelaPlayer.instancia.mostrarFontes(fontes,
          trocaAutomatica: trocaAutomatica, aoFalhar: avisar, aoFuncionar: aoFuncionar, aoVer: aoVer);
    } on ErroLista catch (e) {
      avisar(e.mensagem);
    }
    return;
  }
  final canais = [for (final f in fontes) f.canal];
  final resolver = resolverDasFontes(fontes);
  await _mostrarPagina(
    context,
    (aoSair) => PlayerCanais(
      canais: canais,
      indice: 0,
      nomeLista: fontes.first.lista.nomeMostrado,
      listaDe: (c) => fontes[_indiceDe(fontes, c)].lista.nomeMostrado,
      trocaAutomatica: trocaAutomatica,
      aoFuncionar: aoFuncionar == null ? null : (i) => aoFuncionar(fontes[i]),
      resolver: (c, {continuar = false}) {
        if (!continuar) aoVer?.call(fontes[_indiceDe(fontes, c)]);
        return resolver(c);
      },
      aoSair: aoSair,
      criarSessao: criarSessaoDireto,
      aoTempoVisto: tempoVistoDasFontes(fontes),
    ),
  );
}

/// A fonte de um canal: pela identidade (o mesmo id pode existir em duas listas).
int _indiceDe(List<FonteCanal> fontes, Canal c) => fontes.indexWhere((f) => identical(f.canal, c));

/// O link de cada fonte, pedido com a conta da lista dessa fonte.
Future<FonteVideo> Function(Canal canal) resolverDasFontes(List<FonteCanal> fontes,
    {Future<FonteVideo> Function(Conta conta, Canal canal)? obter}) {
  final pedir = obter ?? (conta, canal) => Protocolo.para(conta).fonte(conta, canal);
  return (c) {
    final i = _indiceDe(fontes, c);
    if (i < 0) return Future.error(ErroLista('canal desconhecido'));
    return pedir(fontes[i].lista.conta, c);
  };
}

/// O tempo visto de cada canal vai para a lista da fonte que o tocou (um contador por lista).
void Function(Canal canal, Duration tempo) tempoVistoDasFontes(List<FonteCanal> fontes,
    {void Function(Canal, Duration) Function(String listaId, String listaNome) criar = contadorDeTempo}) {
  final porLista = <String, void Function(Canal, Duration)>{};
  return (c, d) {
    final i = _indiceDe(fontes, c);
    if (i < 0) return;
    final l = fontes[i].lista;
    (porLista[l.id] ??= criar(l.id, l.nomeMostrado))(c, d);
  };
}

Future<void> _mostrarPagina(BuildContext context, Widget Function(VoidCallback aoSair) player) =>
    Navigator.of(context).push(PageRouteBuilder(
      pageBuilder: (_, _, _) => _PaginaPlayer(player: player),
      transitionDuration: Duration.zero,
      // sem animação ao sair: durante ela a rota de baixo via-se pelo vídeo transparente do ExoPlayer
      reverseTransitionDuration: Duration.zero,
    ));

class _PaginaPlayer extends StatefulWidget {
  const _PaginaPlayer({required this.player});
  final Widget Function(VoidCallback aoSair) player;

  @override
  State<_PaginaPlayer> createState() => _PaginaPlayerState();
}

class _PaginaPlayerState extends State<_PaginaPlayer> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    unawaited(guardarTempoVisto());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // o fundo preto é o do PlayerCanais (transparente com o ExoPlayer, que está por baixo da interface)
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.player(() => Navigator.of(context).maybePop()),
    );
  }
}
