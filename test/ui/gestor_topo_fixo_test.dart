import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/area_gestor.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/tarefas/servico_tarefas.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/gestor/indicador_atividade.dart';
import 'package:player_iptv/ui/gestor/tela_gestor.dart';
import 'package:player_iptv/verificar/servico.dart';

import 'ajuda_dpad.dart';

/// O "i" da verificação (só nos ecrãs Verificar e Verificação) não pode mexer no resto: ao mudar
/// de passo, a faixa dos passos e o conteúdo ficam no mesmo sítio.
void main() {
  // o Windows primeiro: o tema da app (TemaConformeRealce) faz-se uma vez, com a densidade
  // compacta do computador (a que mostrava o salto: o "Voltar" encolhe, o "i" não)
  for (final (nome, largura, altura, tv) in [
    ('Windows 1200×680', 1200.0, 680.0, false),
    ('TV 960×540', 960.0, 540.0, true),
    ('telemóvel 390×844', 390.0, 844.0, false),
  ]) {
    testWidgets('$nome: a faixa dos passos não salta ao entrar em Verificar (onde aparece o "i")', (t) async {
      if (tv) {
        ecraTvTeste(t, largura: largura, altura: altura);
      } else if (largura < 600) {
        t.view.physicalSize = Size(largura, altura);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
      } else {
        t.view.physicalSize = Size(largura, altura);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
      }
      final pasta = Directory.systemTemp.createTempSync('gestor_topo');
      late Biblioteca bib;
      late AreaGestor area;
      await t.runAsync(() async {
        bib = await Biblioteca.abrir(pasta);
        area = await AreaGestor.abrir(pasta);
      });
      addTearDown(() {
        try {
          pasta.deleteSync(recursive: true);
        } on FileSystemException {/* Windows */}
      });
      await t.pumpWidget(appTeste(Scaffold(
          body: TelaGestor(
              biblioteca: bib, area: area, servico: ServicoVerificacao(bib, colecao: area), tarefas: ServicoTarefas()))));
      await t.tap(find.descendant(of: find.byType(CartaoModerno), matching: find.text('Importar')));
      await t.pumpAndSettle();
      final faixa = find.byKey(const ValueKey('faixa 1'));
      final antes = t.getRect(faixa);
      final indicador = find.byType(IndicadorAtividade);
      final indicadorAntes = t.getRect(indicador);
      expect(find.byKey(const ValueKey('infoVerificacao')), findsNothing, reason: 'no Importar não há "i"');
      // o passo 2 pela faixa
      await t.tap(find.byKey(const ValueKey('faixa 2')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('infoVerificacao')), findsOneWidget);
      expect(t.getRect(faixa).top, antes.top, reason: 'a faixa (e o conteúdo por baixo) não desce');
      expect(t.getRect(indicador), indicadorAntes, reason: 'o «Nada a decorrer» não anda para o lado');
      // o foco e o rato no "i" também não mexem em nada
      Map<String, Rect> posicoes() => {
            if (find.text('Verificar listas').evaluate().isNotEmpty) 'titulo': t.getRect(find.text('Verificar listas')),
            'faixa': t.getRect(faixa),
            'i': t.getRect(find.byKey(const ValueKey('infoVerificacao'))),
          };
      final semFoco = posicoes();
      Focus.of(t.element(find.byIcon(Icons.info_outline))).requestFocus();
      await t.pumpAndSettle();
      expect(posicoes(), semFoco, reason: 'com o foco no "i"');
      final rato = await t.createGesture(kind: PointerDeviceKind.mouse);
      await rato.addPointer(location: Offset.zero);
      addTearDown(rato.removePointer);
      await rato.moveTo(t.getCenter(find.byKey(const ValueKey('infoVerificacao'))));
      await t.pumpAndSettle();
      expect(posicoes(), semFoco, reason: 'com o rato no "i"');
    });
  }
}
