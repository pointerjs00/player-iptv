import 'package:material_ui/material_ui.dart';

import 'realce_foco.dart';

/// Cores do verificador (tema escuro).
abstract final class Cores {
  static const fundo = Color(0xFF0E1116);
  static const superficie = Color(0xFF161B22);
  static const superficie2 = Color(0xFF1F2630);
  static const borda = Color(0xFF2D3440);
  static const texto = Color(0xFFE6EDF3);
  static const texto2 = Color(0xFF9AA6B2);
  static const acento = Color(0xFF7C9CFF);
  static const ok = Color(0xFF3FB950);
  static const mau = Color(0xFFF85149);
  static const aviso = Color(0xFFD29922);
}

/// O tema da app. `realceFoco`: as bordas/fundos de foco para o comando (ver [TemaConformeRealce],
/// que troca entre os dois conforme o modo de realce: no telemóvel/rato não há borda).
ThemeData temaApp({bool realceFoco = true}) {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Cores.acento, brightness: Brightness.dark, surface: Cores.superficie,
    ),
    scaffoldBackgroundColor: Cores.fundo,
    useMaterial3: true,
  );
  return base.copyWith(
    cardTheme: const CardThemeData(
      color: Cores.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Cores.borda),
      ),
      margin: EdgeInsets.zero,
    ),
    // o foco tem de se ver bem na TV: borda de 3 px e fundo mais claro em tudo o que é focável
    focusColor: realceFoco ? _fundoFoco : null,
    filledButtonTheme: realceFoco ? FilledButtonThemeData(style: _focoBotao(_bordaFocoClara)) : null,
    elevatedButtonTheme: realceFoco ? ElevatedButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    outlinedButtonTheme: realceFoco ? OutlinedButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    textButtonTheme: realceFoco ? TextButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    iconButtonTheme: realceFoco ? IconButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    segmentedButtonTheme: realceFoco ? SegmentedButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    // o mesmo objeto nos dois temas: o ChipThemeData.lerp falha com um side que resolve a null
    // (só não interpola se for idêntico); o resolvedor já vê o modo de realce
    chipTheme: _temaChips,
    tabBarTheme: realceFoco ? TabBarThemeData(overlayColor: _seFocado(_fundoFoco)) : null,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie2,
      isDense: true,
      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
      focusedBorder: realceFoco
          ? const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10)), borderSide: _bordaFoco)
          : null,
    ),
  );
}

const _bordaFoco = Realce.borda;
final _temaChips =
    ChipThemeData(side: WidgetStateBorderSide.resolveWith((s) => _focoVisivel(s) ? _bordaFoco : null));
const _bordaFocoClara = Realce.bordaClara;
final _fundoFoco = Realce.fundo;

/// `v` só no estado focado e com o realce do teclado/comando (no telemóvel ou com o rato, um
/// botão com foco automático não ganha borda); nos outros casos fica o valor por omissão.
bool _focoVisivel(Set<WidgetState> s) =>
    s.contains(WidgetState.focused) && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

WidgetStateProperty<T?> _seFocado<T>(T v) => WidgetStateProperty.resolveWith((s) => _focoVisivel(s) ? v : null);

ButtonStyle _focoBotao(BorderSide borda) => ButtonStyle(side: _seFocado(borda), overlayColor: _seFocado(_fundoFoco));

/// Cor e texto de um estado da verificação.
(Color, String, IconData) visualEstado(String? estado) => switch (estado) {
      'funciona' => (Cores.ok, 'Funciona', Icons.check_circle_outline),
      'nao_funciona' => (Cores.mau, 'Não funciona', Icons.cancel_outlined),
      'inconclusivo' => (Cores.aviso, 'Inconclusivo', Icons.warning_amber_rounded),
      _ => (Cores.texto2, 'Por verificar', Icons.help_outline),
    };

/// "há 2 dias", "hoje às 14:05"...
String dataRelativa(DateTime d, [DateTime? agora]) {
  final a = agora ?? DateTime.now();
  final dias = DateTime(a.year, a.month, a.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  String hm() => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (dias <= 0) return 'hoje às ${hm()}';
  if (dias == 1) return 'ontem às ${hm()}';
  if (dias < 30) return 'há $dias dias';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

/// "até 16/10/2027", "sem limite" ou "".
String textoValidade(String v) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
  if (m != null) return 'até ${m[3]}/${m[2]}/${m[1]}';
  return v == 'sem limite' ? 'sem limite' : '';
}
