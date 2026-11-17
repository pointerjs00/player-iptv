import 'package:flutter/services.dart';

import 'numero_canal.dart';

/// O que está por cima do vídeo.
enum VistaPlayer {
  /// Só o vídeo: as setas mudam de canal (cima = seguinte, baixo = anterior) e recuam/avançam (esquerda/direita).
  escondida,

  /// A barra de controlos: as setas andam pelos botões.
  controlos,

  /// O painel de definições (aberto a partir da barra): as setas andam pelo painel.
  painel,
}

/// O que o player tem de fazer com uma tecla.
enum AcaoPlayer {
  /// Nada aqui: a tecla segue (as setas/OK movem o foco ou carregam no botão focado).
  passar,
  mostrarControlos,
  esconderControlos,
  fecharPainel,
  sair,
  canalAnterior,
  canalSeguinte,
  recuar,
  avancar,
  playPausa,
  tocar,
  pausar,
  estatisticas,
  ecraInteiro,
  tentarDeNovo,

  /// (só dos botões) seek até ao fim do buffer.
  voltarAoDireto,

  /// Um algarismo entrou (ou saiu) do número do canal ([MaquinaControlos.numero]).
  algarismo,

  /// Saltar para o canal com o número escrito ([MaquinaControlos.tirarNumero]).
  irParaNumero,

  /// O número escrito foi abandonado (Voltar).
  cancelarNumero,

  /// Alternar entre os dois últimos canais vistos.
  alternarCanal,
}

/// As teclas do comando/teclado no player, conforme a vista. Sem widgets (testa-se à parte):
/// o player faz a ação devolvida.
class MaquinaControlos {
  VistaPlayer vista = VistaPlayer.escondida;

  static final _ok = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  static final _voltar = {LogicalKeyboardKey.goBack, LogicalKeyboardKey.escape, LogicalKeyboardKey.browserBack};

  /// Funcionam sempre, mesmo com a barra ou o painel abertos.
  static final _sempre = {
    LogicalKeyboardKey.mediaPlayPause: AcaoPlayer.playPausa,
    LogicalKeyboardKey.mediaPlay: AcaoPlayer.tocar,
    LogicalKeyboardKey.mediaPause: AcaoPlayer.pausar,
    LogicalKeyboardKey.mediaRewind: AcaoPlayer.recuar,
    LogicalKeyboardKey.mediaFastForward: AcaoPlayer.avancar,
    // Canal+ = o canal seguinte (convenção da TV), como ↑ e o deslizar para cima
    LogicalKeyboardKey.channelUp: AcaoPlayer.canalSeguinte,
    LogicalKeyboardKey.channelDown: AcaoPlayer.canalAnterior,
    LogicalKeyboardKey.pageUp: AcaoPlayer.canalSeguinte,
    LogicalKeyboardKey.pageDown: AcaoPlayer.canalAnterior,
    LogicalKeyboardKey.info: AcaoPlayer.estatisticas,
    LogicalKeyboardKey.contextMenu: AcaoPlayer.estatisticas,
    LogicalKeyboardKey.keyI: AcaoPlayer.estatisticas,
    LogicalKeyboardKey.f11: AcaoPlayer.ecraInteiro,
    // a tecla "último canal" do comando (KEYCODE_LAST_CHANNEL)
    LogicalKeyboardKey.mediaLast: AcaoPlayer.alternarCanal,
  };

  /// Só com o vídeo sozinho (com a barra, as setas são da navegação).
  static final _escondida = {
    LogicalKeyboardKey.arrowUp: AcaoPlayer.canalSeguinte,
    LogicalKeyboardKey.arrowDown: AcaoPlayer.canalAnterior,
    LogicalKeyboardKey.arrowLeft: AcaoPlayer.recuar,
    LogicalKeyboardKey.arrowRight: AcaoPlayer.avancar,
    LogicalKeyboardKey.space: AcaoPlayer.playPausa,
    LogicalKeyboardKey.backspace: AcaoPlayer.alternarCanal,
  };

  /// O número do canal a ser escrito com os algarismos ('' = nenhum).
  String numero = '';

  /// O número escrito (e esquece-o). null = não havia.
  int? tirarNumero() {
    final n = int.tryParse(numero);
    numero = '';
    return n;
  }

  /// A ação de uma tecla premida (`erro`: está à vista o cartão de erro do canal).
  AcaoPlayer tecla(LogicalKeyboardKey k, {bool erro = false}) {
    // os algarismos escrevem o número do canal em qualquer vista (nenhuma outra tecla os usa)
    final d = algarismoDe(k);
    if (d != null) {
      if (numero.length < maxAlgarismos) numero += '$d';
      return AcaoPlayer.algarismo;
    }
    if (numero.isNotEmpty) {
      if (_ok.contains(k)) return AcaoPlayer.irParaNumero;
      if (k == LogicalKeyboardKey.backspace) {
        numero = numero.substring(0, numero.length - 1);
        return numero.isEmpty ? AcaoPlayer.cancelarNumero : AcaoPlayer.algarismo;
      }
    }
    final sempre = _sempre[k];
    if (sempre != null) return sempre;
    if (_voltar.contains(k)) return voltar();
    if (vista != VistaPlayer.escondida) return AcaoPlayer.passar;
    if (_ok.contains(k)) {
      if (erro) return AcaoPlayer.tentarDeNovo;
      vista = VistaPlayer.controlos;
      return AcaoPlayer.mostrarControlos;
    }
    return _escondida[k] ?? AcaoPlayer.passar;
  }

  /// Voltar por camadas: abandona o número a ser escrito, fecha o painel, depois a barra, depois sai.
  AcaoPlayer voltar() {
    if (numero.isNotEmpty) {
      numero = '';
      return AcaoPlayer.cancelarNumero;
    }
    switch (vista) {
      case VistaPlayer.painel:
        vista = VistaPlayer.controlos;
        return AcaoPlayer.fecharPainel;
      case VistaPlayer.controlos:
        vista = VistaPlayer.escondida;
        return AcaoPlayer.esconderControlos;
      case VistaPlayer.escondida:
        return AcaoPlayer.sair;
    }
  }

  /// Mostra a barra (toque, rato); com o painel aberto fica o painel.
  void mostrar() {
    if (vista == VistaPlayer.escondida) vista = VistaPlayer.controlos;
  }

  void abrirPainel() => vista = VistaPlayer.painel;

  void esconder() => vista = VistaPlayer.escondida;
}
