import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/maquina_controlos.dart';

typedef K = LogicalKeyboardKey;

MaquinaControlos _em(VistaPlayer v) => MaquinaControlos()..vista = v;

void main() {
  group('controlos escondidos', () {
    test('cima/baixo mudam de canal; esquerda/direita recuam/avançam 10 s', () {
      final m = MaquinaControlos();
      expect(m.vista, VistaPlayer.escondida);
      expect(m.tecla(K.arrowUp), AcaoPlayer.canalAnterior);
      expect(m.tecla(K.arrowDown), AcaoPlayer.canalSeguinte);
      expect(m.tecla(K.arrowLeft), AcaoPlayer.recuar);
      expect(m.tecla(K.arrowRight), AcaoPlayer.avancar);
      expect(m.vista, VistaPlayer.escondida);
    });

    test('OK (select/enter) mostra os controlos', () {
      for (final k in [K.select, K.enter, K.numpadEnter, K.gameButtonA]) {
        final m = MaquinaControlos();
        expect(m.tecla(k), AcaoPlayer.mostrarControlos);
        expect(m.vista, VistaPlayer.controlos);
      }
    });

    test('com o cartão de erro, OK tenta de novo', () {
      final m = MaquinaControlos();
      expect(m.tecla(K.select, erro: true), AcaoPlayer.tentarDeNovo);
      expect(m.vista, VistaPlayer.escondida);
    });

    test('Voltar/Esc sai do player', () {
      expect(MaquinaControlos().tecla(K.goBack), AcaoPlayer.sair);
      expect(MaquinaControlos().tecla(K.escape), AcaoPlayer.sair);
    });
  });

  group('controlos visíveis', () {
    test('as setas e o OK ficam para a barra (navegação do foco), não mudam de canal', () {
      final m = _em(VistaPlayer.controlos);
      for (final k in [K.arrowUp, K.arrowDown, K.arrowLeft, K.arrowRight, K.select, K.enter]) {
        expect(m.tecla(k), AcaoPlayer.passar, reason: '$k');
      }
      expect(m.vista, VistaPlayer.controlos);
    });

    test('Voltar esconde os controlos', () {
      final m = _em(VistaPlayer.controlos);
      expect(m.tecla(K.goBack), AcaoPlayer.esconderControlos);
      expect(m.vista, VistaPlayer.escondida);
    });
  });

  group('painel de definições aberto', () {
    test('as setas e o OK ficam para o painel', () {
      final m = _em(VistaPlayer.painel);
      for (final k in [K.arrowUp, K.arrowDown, K.arrowLeft, K.arrowRight, K.select]) {
        expect(m.tecla(k), AcaoPlayer.passar, reason: '$k');
      }
    });

    test('Voltar por camadas: painel → controlos → escondido → sair', () {
      final m = _em(VistaPlayer.painel);
      expect(m.tecla(K.goBack), AcaoPlayer.fecharPainel);
      expect(m.vista, VistaPlayer.controlos);
      expect(m.tecla(K.escape), AcaoPlayer.esconderControlos);
      expect(m.vista, VistaPlayer.escondida);
      expect(m.tecla(K.goBack), AcaoPlayer.sair);
    });
  });

  test('o Voltar do sistema (sem tecla: PopScope) segue as mesmas camadas', () {
    final m = _em(VistaPlayer.painel);
    expect(m.voltar(), AcaoPlayer.fecharPainel);
    expect(m.voltar(), AcaoPlayer.esconderControlos);
    expect(m.voltar(), AcaoPlayer.sair);
    expect(m.vista, VistaPlayer.escondida);
  });

  test('teclas multimédia funcionam sempre, em qualquer vista', () {
    for (final v in VistaPlayer.values) {
      expect(_em(v).tecla(K.mediaPlayPause), AcaoPlayer.playPausa, reason: '$v');
      expect(_em(v).tecla(K.mediaPlay), AcaoPlayer.tocar);
      expect(_em(v).tecla(K.mediaPause), AcaoPlayer.pausar);
      expect(_em(v).tecla(K.mediaRewind), AcaoPlayer.recuar);
      expect(_em(v).tecla(K.mediaFastForward), AcaoPlayer.avancar);
      expect(_em(v).tecla(K.channelUp), AcaoPlayer.canalAnterior);
      expect(_em(v).tecla(K.channelDown), AcaoPlayer.canalSeguinte);
      expect(_em(v).tecla(K.pageUp), AcaoPlayer.canalAnterior);
      expect(_em(v).tecla(K.pageDown), AcaoPlayer.canalSeguinte);
      expect(_em(v).tecla(K.info), AcaoPlayer.estatisticas);
      expect(_em(v).tecla(K.f11), AcaoPlayer.ecraInteiro);
      final m = _em(v);
      m.tecla(K.mediaPlayPause);
      expect(m.vista, v, reason: 'as teclas multimédia não mudam a vista');
    }
  });

  test('o espaço faz play/pausa só com os controlos escondidos (com eles carrega no botão focado)', () {
    expect(MaquinaControlos().tecla(K.space), AcaoPlayer.playPausa);
    expect(_em(VistaPlayer.controlos).tecla(K.space), AcaoPlayer.passar);
  });

  test('outras teclas passam', () {
    expect(MaquinaControlos().tecla(K.keyZ), AcaoPlayer.passar);
  });

  test('mostrar / abrir painel / esconder', () {
    final m = MaquinaControlos()..mostrar();
    expect(m.vista, VistaPlayer.controlos);
    m.abrirPainel();
    expect(m.vista, VistaPlayer.painel);
    m.mostrar(); // mostrar com o painel aberto não o fecha
    expect(m.vista, VistaPlayer.painel);
    m.esconder();
    expect(m.vista, VistaPlayer.escondida);
  });
}
