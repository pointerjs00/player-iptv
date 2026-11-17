import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/biblioteca.dart';
import '../../janelas/janela_player.dart';
import '../../modelo/canal.dart';
import '../../protocolos/protocolo.dart';
import 'player_canais.dart';

/// Abre o canal: no Windows numa janela separada; no Android em ecrã inteiro. No Android
/// devolve, ao sair do player, o índice do canal que estava a tocar (pode ter mudado).
/// `aoVer` é chamado com cada canal que o player abre (o primeiro e os do zapping).
Future<int?> abrirCanal(BuildContext context, Lista lista, List<Canal> canais, int i,
    {ValueChanged<Canal>? aoVer}) async {
  if (Platform.isWindows) {
    final avisos = ScaffoldMessenger.maybeOf(context);
    void avisar(String m) => avisos?.showSnackBar(SnackBar(content: Text(m)));
    try {
      await JanelaPlayer.instancia.mostrar(lista, canais, i, aoFalhar: avisar, aoVer: aoVer);
    } on ErroLista catch (e) {
      avisar(e.mensagem);
    }
    return null;
  }
  final atual = ValueNotifier(i);
  await Navigator.of(context).push(PageRouteBuilder(
    pageBuilder: (_, _, _) => _PaginaPlayer(lista: lista, canais: canais, i: i, atual: atual, aoVer: aoVer),
    transitionDuration: Duration.zero,
  ));
  return atual.value;
}

class _PaginaPlayer extends StatefulWidget {
  const _PaginaPlayer({required this.lista, required this.canais, required this.i, required this.atual, this.aoVer});
  final ValueNotifier<int> atual;
  final ValueChanged<Canal>? aoVer;
  final Lista lista;
  final List<Canal> canais;
  final int i;

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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conta = widget.lista.conta;
    return Scaffold(
      backgroundColor: Colors.black,
      body: PlayerCanais(
        canais: widget.canais,
        indice: widget.i,
        nomeLista: widget.lista.nomeMostrado,
        resolver: (c) {
          widget.aoVer?.call(c);
          return Protocolo.para(conta).fonte(conta, c);
        },
        aoSair: () => Navigator.of(context).maybePop(),
        aoMudarCanal: (i) => widget.atual.value = i,
      ),
    );
  }
}
