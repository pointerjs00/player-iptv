import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/cartao_erro.dart';
import 'package:player_iptv/ui/player/controlos_player.dart';
import 'package:player_iptv/ui/player/maquina_controlos.dart';
import 'package:player_iptv/ui/tema.dart';

class _Ensaio {
  final acoes = <AcaoPlayer>[];
  var tentativas = 0;
  var voltas = 0;
  var erro = true;
  StateSetter? reconstruir;
}

Future<_Ensaio> _montar(WidgetTester t) async {
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  t.view.physicalSize = const Size(1920, 1080);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final e = _Ensaio();
  await t.pumpWidget(MaterialApp(
    theme: temaApp(),
    home: Scaffold(
      backgroundColor: Colors.black,
      body: StatefulBuilder(builder: (_, setState) {
        e.reconstruir = setState;
        return ControlosPlayer(
          estado: EstadoControlos(canal: 'RTP 1', subtitulo: 'Generalistas · 3/120 · Lista A', erro: e.erro),
          atraso: () => Duration.zero,
          aoAgir: e.acoes.add,
          aoMudarVelocidade: (_) {},
          definicoes: () => const [],
          child: Stack(fit: StackFit.expand, children: [
            if (e.erro)
              CartaoErroCanal(
                texto: 'RTP 1: o canal não começou a tempo (sem imagem em 20 s)',
                aoTentar: () => e.tentativas++,
                aoVoltar: () => e.voltas++,
              ),
          ]),
        );
      }),
    ),
  ));
  await t.pumpAndSettle();
  return e;
}

Future<void> _tecla(WidgetTester t, LogicalKeyboardKey k) async {
  await t.sendKeyEvent(k);
  await t.pumpAndSettle();
}

String? _focado() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final texto = find.descendant(of: find.byWidget(ctx.widget), matching: find.byType(Text));
  return texto.evaluate().isEmpty ? null : (texto.evaluate().first.widget as Text).data;
}

void main() {
  testWidgets('cartão de erro: o foco começa em "Tentar de novo"; OK tenta de novo', (t) async {
    final e = await _montar(t);
    expect(_focado(), 'Tentar de novo');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(e.tentativas, 1);
    expect(e.voltas, 0);
    expect(e.acoes, isEmpty, reason: 'o OK é do botão, não do player');
  });

  testWidgets('cartão de erro: direita leva o foco a "Voltar" e OK volta (sem recuar/avançar no canal)', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    expect(_focado(), 'Voltar');
    await _tecla(t, LogicalKeyboardKey.select);
    expect(e.voltas, 1);
    expect(e.tentativas, 0);
    await _tecla(t, LogicalKeyboardKey.arrowLeft);
    expect(_focado(), 'Tentar de novo');
    expect(e.acoes, isEmpty, reason: 'esquerda/direita não recuam nem avançam com o cartão à vista');
  });

  testWidgets('cartão de erro: cima/baixo continuam a mudar de canal', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    await _tecla(t, LogicalKeyboardKey.arrowDown);
    expect(e.acoes, [AcaoPlayer.canalSeguinte, AcaoPlayer.canalAnterior]);
  });

  testWidgets('depois de o cartão sair, as teclas voltam ao player (direita avança)', (t) async {
    final e = await _montar(t);
    await _tecla(t, LogicalKeyboardKey.arrowRight); // foco em "Voltar"
    e.reconstruir!(() => e.erro = false);
    await t.pumpAndSettle();
    await _tecla(t, LogicalKeyboardKey.arrowRight);
    await _tecla(t, LogicalKeyboardKey.arrowUp);
    expect(e.acoes, [AcaoPlayer.avancar, AcaoPlayer.canalSeguinte]);
  });
}
