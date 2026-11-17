import 'package:material_ui/material_ui.dart';

/// Os valores do design "cinema": cores, raios, espaçamentos, sombras, durações e curvas.
/// Todos os ecrãs usam estes valores (nada de cores soltas nos widgets).
abstract final class Tokens {
  // --- cores ---
  /// Fundo azul-noite.
  static const fundo = Color(0xFF0B0F17);

  /// O centro do gradiente radial subtil do fundo.
  static const fundoBrilho = Color(0xFF18203A);

  /// Superfícies opacas (diálogos, menus, barras) — o "vidro" sobre o fundo.
  static const superficie = Color(0xFF131925);
  static const superficie2 = Color(0xFF1B2232);

  /// Vidro fosco: branco a 4 / 6 / 8 %.
  static const vidroFraco = Color(0x0AFFFFFF);
  static const vidro = Color(0x0FFFFFFF);
  static const vidroForte = Color(0x14FFFFFF);

  /// A borda do vidro: branco a 8 %.
  static const bordaVidro = Color(0x14FFFFFF);

  static const texto = Color(0xFFE8ECF4);

  /// Texto secundário: o texto a 60 %.
  static const texto2 = Color(0x99E8ECF4);

  /// Acento: índigo → violeta.
  static const acento = Color(0xFF6C7BFF);
  static const acento2 = Color(0xFF9B6CFF);
  static const gradienteAcento = LinearGradient(colors: [acento, acento2]);

  // estados (pílulas)
  static const ok = Color(0xFF3FCF7A);
  static const mau = Color(0xFFFF5D5D);
  static const aviso = Color(0xFFF2B33D);
  static const neutro = Color(0xFF8E98AC);

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

  // --- sombras (em camadas: uma curta e nítida + uma longa e difusa). Só por fora (outer):
  // por baixo do vidro translúcido escureceriam o cartão ---
  static const sombra1 = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1), blurStyle: BlurStyle.outer),
    BoxShadow(color: Color(0x26000000), blurRadius: 12, offset: Offset(0, 4), blurStyle: BlurStyle.outer),
  ];
  static const sombra2 = [
    BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2), blurStyle: BlurStyle.outer),
    BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 10), blurStyle: BlurStyle.outer),
  ];
  static const sombra3 = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 3), blurStyle: BlurStyle.outer),
    BoxShadow(color: Color(0x59000000), blurRadius: 40, offset: Offset(0, 18), blurStyle: BlurStyle.outer),
  ];

  /// Com o foco do comando: a sombra mais alta e um brilho violeta.
  static const sombraFoco = [
    ...sombra3,
    BoxShadow(color: Color(0x739B6CFF), blurRadius: 28, spreadRadius: 1, blurStyle: BlurStyle.outer),
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
