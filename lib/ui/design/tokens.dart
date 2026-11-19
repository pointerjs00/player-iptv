import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Os valores do design "cinema": cores, raios, espaçamentos, sombras, durações e curvas.
/// Todos os ecrãs usam estes valores (nada de cores soltas nos widgets).
abstract final class Tokens {
  // --- cores ---
  /// Fundo azul-noite.
  static const fundo = Color(0xFF0A1628);

  /// O centro do gradiente radial subtil do fundo.
  static const fundoBrilho = Color(0xFF18203A);

  /// Superfícies opacas (diálogos, menus, barras) — o "vidro" sobre o fundo.
  static const superficie = Color(0xFF0D1F3A);
  static const superficie2 = Color(0xFF132B4D);
  static const superficie3 = Color(0xFF1A3A66);

  /// Vidro fosco: branco a 4 / 6 / 8 %.
  static const vidroFraco = Color(0x0AFFFFFF);
  static const vidro = Color(0x0FFFFFFF);
  static const vidroForte = Color(0x14FFFFFF);

  /// A borda do vidro: branco a 8 %.
  static const bordaVidro = Color(0x14FFFFFF);

  static const texto = Color(0xFFEEF4FF);

  /// Texto secundário: opaco, para o contraste ser verificável (ver [contraste]).
  static const texto2 = Color(0xFFA3B8D6);

  /// Acento: azul → azul-escuro.
  static const acento = Color(0xFF2F7BF6);
  static const acento2 = Color(0xFF1E5BB8);
  static const gradienteAcento = LinearGradient(colors: [acento, acento2]);

  /// O anel de foco (comando da TV): azul claro, bem visível sobre o fundo escuro.
  static const anelFoco = Color(0xFF8EC5FF);

  // estados (pílulas)
  static const ok = Color(0xFF5EE0A0);
  static const mau = Color(0xFFFF9A9A);
  static const aviso = Color(0xFFFFD27A);
  static const neutro = Color(0xFFA3B8D6);

  /// Fundos opacos das pílulas de estado (o texto de cada estado tem contraste ≥ 4,5 sobre eles).
  static const fundoOk = Color(0xFF123F33);
  static const fundoAviso = Color(0xFF4A3A12);
  static const fundoMau = Color(0xFF4A1E24);
  static const fundoNeutro = Color(0xFF22324A);

  // --- raios ---
  static const raioCartao = 20.0;
  static const raioBotao = 14.0;
  static const raioCampo = 12.0;
  static const raioPilula = 999.0;

  // --- espaçamentos ---
  static const e4 = 4.0;
  static const e8 = 8.0;
  static const e12 = 12.0;
  static const e16 = 16.0;
  static const e24 = 24.0;
  static const e32 = 32.0;

  /// A altura das linhas das tabelas do Gestor (passos 2 e 3): fixa e baixa (na TV cabem pelo
  /// menos 12).
  static const alturaLinhaTabela = 32.0;

  // --- sombras (em camadas: uma curta e nítida + uma longa e difusa); pintadas só por fora
  // das superfícies de vidro (ver SombraExterior) ---
  static const sombra1 = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const sombra2 = [
    BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10)),
  ];
  static const sombra3 = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 18)),
  ];

  /// Com o foco do comando: a sombra mais alta e um brilho azul.
  static const sombraFoco = [
    ...sombra3,
    BoxShadow(color: Color(0x738EC5FF), blurRadius: 28, spreadRadius: 1),
  ];

  /// As sombras de uma elevação (0 = nenhuma, 1–3).
  static List<BoxShadow> sombra(int elevacao) => switch (elevacao) {
        <= 0 => const [],
        1 => sombra1,
        2 => sombra2,
        _ => sombra3,
      };

  // --- movimento ---
  static const duracaoRapida = Duration(milliseconds: 180);
  static const duracaoMedia = Duration(milliseconds: 240);
  static const duracaoLenta = Duration(milliseconds: 320);
  static const curva = Curves.easeOutCubic;
}

/// A razão de contraste WCAG entre duas cores (1 a 21); o texto normal pede ≥ 4,5.
double contraste(Color a, Color b) {
  double lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
