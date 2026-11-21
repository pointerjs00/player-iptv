import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/design/componentes.dart';
import 'package:player_iptv/ui/realce_foco.dart';
import 'package:player_iptv/ui/tema.dart';

/// Ajudas partilhadas pelos testes do telemóvel (360×800 e 412×915, letra a 1 e a 1,3, com a
/// Roboto): carregar a letra, montar a app, correr em cada configuração (nada transborda) e
/// medir texto e alvos.

/// A Roboto do Flutter (a letra do telemóvel), também no lugar da letra quadrada dos testes: com
/// ela as larguras seriam outras.
Future<void> carregarRoboto() async {
  // <flutter>/bin/cache/artifacts/engine/<plataforma>/flutter_tester
  final artefactos = File(Platform.resolvedExecutable).parent.parent.parent;
  final pasta = Directory('${artefactos.path}/material_fonts');
  if (!pasta.existsSync()) fail('A Roboto do Flutter não está em ${pasta.path}');
  for (final familia in ['Roboto', 'FlutterTest']) {
    final f = FontLoader(familia);
    for (final n in ['roboto-light', 'roboto-regular', 'roboto-medium', 'roboto-bold', 'roboto-black']) {
      f.addFont(Future.value(ByteData.sublistView(File('${pasta.path}/$n.ttf').readAsBytesSync())));
    }
    await f.load();
  }
}

/// A app como no telemóvel: o fundo do design e a Roboto também nos chips (o rótulo deles não
/// diz a família: no telemóvel é a do sistema, a Roboto; no teste seria a letra quadrada).
Widget appTelemovel(Widget home) => MaterialApp(
  theme: temaApp(),
  builder: (_, w) => TemaConformeRealce(
    child: Builder(
      builder: (c) {
        final tema = Theme.of(c);
        final chips = tema.chipTheme;
        return Theme(
          data: tema.copyWith(
            chipTheme: chips.copyWith(
              labelStyle: (chips.labelStyle ?? const TextStyle()).copyWith(fontFamily: 'Roboto'),
            ),
          ),
          child: FundoCinema(child: w!),
        );
      },
    ),
  ),
  home: home,
);

const configsTelemovel = [(360.0, 800.0, 1.0), (360.0, 800.0, 1.3), (412.0, 915.0, 1.0), (412.0, 915.0, 1.3)];

/// Corre [corpo] em cada telemóvel de [configs]; no fim, nenhum erro (overflow incluído).
void noTelemovel(
  String nome,
  Future<void> Function(WidgetTester t, Size ecra) corpo, {
  List<(double, double, double)> configs = configsTelemovel,
}) {
  for (final (l, a, e) in configs) {
    testWidgets('$nome · ${l.toInt()}×${a.toInt()} · letra $e', (t) async {
      t.view.physicalSize = Size(l, a);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = e;
      addTearDown(t.view.reset);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final erros = <String>[];
      final antes = FlutterError.onError;
      FlutterError.onError = (d) => erros.add(d.exceptionAsString().split('\n').first);
      try {
        await corpo(t, Size(l, a));
      } finally {
        FlutterError.onError = antes;
      }
      expect(erros, isEmpty, reason: 'sem overflow nem outros erros');
      expect(t.takeException(), isNull);
    });
  }
}

/// O texto não foi cortado (nem com reticências, nem por faltarem linhas).
void inteiro(WidgetTester t, Finder texto) {
  final p = paragrafo(t, texto);
  expect(p.didExceedMaxLines, isFalse, reason: '«${p.text.toPlainText()}» cortado');
}

/// O parágrafo de um `Text` (também com `semanticsLabel`, que o embrulha num `Semantics`).
RenderParagraph paragrafo(WidgetTester t, Finder texto) =>
    t.renderObject<RenderParagraph>(find.descendant(of: texto, matching: find.byType(RichText), matchRoot: true).first);

/// O texto cabe todo na caixa que o desenha (sem reticências nem corte).
void semReticencias(WidgetTester t, Finder texto) {
  final p = paragrafo(t, texto);
  final s = p.text.toPlainText();
  expect(p.didExceedMaxLines, isFalse, reason: '«$s» cortado');
  final fim = p.getOffsetForCaret(TextPosition(offset: s.length), Rect.zero);
  expect(fim.dx, lessThanOrEqualTo(p.size.width + .5), reason: '«$s» passa a largura');
  expect(
    p.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(p.size.width + .5),
    reason: '«$s» não cabe numa linha mas não parte',
  );
}

/// O alvo de toque tem pelo menos 48×48.
void alvo48(WidgetTester t, Finder f, {String? motivo}) {
  final s = t.getSize(f);
  expect(s.width, greaterThanOrEqualTo(48), reason: motivo);
  expect(s.height, greaterThanOrEqualTo(48), reason: motivo);
}

/// Todo dentro do ecrã (sem deslizar nada).
void noEcra(WidgetTester t, Finder f, Size ecra, {String? motivo}) {
  final r = t.getRect(f);
  expect(r.left, greaterThanOrEqualTo(0), reason: motivo);
  expect(r.top, greaterThanOrEqualTo(0), reason: motivo);
  expect(r.right, lessThanOrEqualTo(ecra.width + .5), reason: motivo);
  expect(r.bottom, lessThanOrEqualTo(ecra.height + .5), reason: motivo);
}

