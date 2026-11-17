import 'package:material_ui/material_ui.dart';

import 'design/movimento.dart';
import 'design/tokens.dart';
import 'realce_foco.dart';

/// As cores da app (atalhos para os [Tokens] do design "cinema").
abstract final class Cores {
  static const fundo = Tokens.fundo;
  static const superficie = Tokens.superficie;
  static const superficie2 = Tokens.superficie2;
  static const borda = Tokens.bordaVidro;
  static const texto = Tokens.texto;
  static const texto2 = Tokens.texto2;
  static const acento = Tokens.acento;
  static const ok = Tokens.ok;
  static const mau = Tokens.mau;
  static const aviso = Tokens.aviso;
}

/// O tema da app. `realceFoco`: as bordas/fundos de foco para o comando (ver [TemaConformeRealce],
/// que troca entre os dois conforme o modo de realce: no telemóvel/rato não há borda).
ThemeData temaApp({bool realceFoco = true}) {
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Tokens.acento, brightness: Brightness.dark, surface: Tokens.superficie,
    ).copyWith(
      primary: Tokens.acento,
      onPrimary: Colors.white,
      secondary: Tokens.acento2,
      onSurface: Tokens.texto,
      onSurfaceVariant: Tokens.texto2,
      outline: Tokens.bordaVidro,
      outlineVariant: Tokens.bordaVidro,
    ),
    // o fundo (azul-noite com gradiente) é o FundoCinema por trás de todos os ecrãs
    scaffoldBackgroundColor: Colors.transparent,
    useMaterial3: true,
  );
  const raioBotao = BorderRadius.all(Radius.circular(Tokens.raioBotao));
  const raioCampo = BorderRadius.all(Radius.circular(Tokens.raioCampo));
  const formaBotao = WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: raioBotao));
  const bordaCampo = OutlineInputBorder(borderRadius: raioCampo, borderSide: BorderSide(color: Tokens.bordaVidro));
  final texto = base.textTheme.apply(bodyColor: Tokens.texto, displayColor: Tokens.texto);
  return base.copyWith(
    textTheme: texto.copyWith(
      titleLarge: texto.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: texto.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: texto.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: texto.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final p in TargetPlatform.values) p: const TransicaoSuaveBuilder(),
    }),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: Tokens.texto,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto, letterSpacing: .2),
    ),
    cardTheme: const CardThemeData(
      color: Tokens.vidro,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Tokens.raioCartao)),
        side: BorderSide(color: Tokens.bordaVidro),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Tokens.superficie,
      surfaceTintColor: Colors.transparent,
      barrierColor: Color(0xB305070C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Tokens.raioCartao)),
        side: BorderSide(color: Tokens.bordaVidro),
      ),
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Tokens.texto),
    ),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: Tokens.superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Tokens.raioCartao))),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: Tokens.superficie2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: raioBotao,
        side: BorderSide(color: Tokens.bordaVidro),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Tokens.superficie2,
      contentTextStyle: TextStyle(color: Tokens.texto),
      shape: RoundedRectangleBorder(borderRadius: raioBotao, side: BorderSide(color: Tokens.bordaVidro)),
    ),
    dividerTheme: const DividerThemeData(color: Tokens.bordaVidro, space: 1),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: raioCampo),
      selectedColor: Tokens.texto,
      selectedTileColor: Color(0x2E6C7BFF),
      iconColor: Tokens.texto2,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Tokens.acento : null),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Tokens.acento,
      linearTrackColor: Tokens.vidroForte,
      borderRadius: BorderRadius.all(Radius.circular(99)),
    ),
    // o foco tem de se ver bem na TV: borda de 3 px e fundo mais claro em tudo o que é focável
    focusColor: realceFoco ? _fundoFoco : null,
    hoverColor: Tokens.vidro,
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: formaBotao,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled) ? Tokens.texto2 : Colors.white),
        backgroundBuilder: _fundoGradiente,
        side: realceFoco ? _seFocado(_bordaFocoClara) : null,
        overlayColor: realceFoco ? _seFocado(_fundoFoco) : null,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(style: _estiloBotao(realceFoco)),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _estiloBotao(realceFoco, lado: const BorderSide(color: Color(0x29FFFFFF))),
    ),
    textButtonTheme: TextButtonThemeData(style: _estiloBotao(realceFoco)),
    iconButtonTheme: realceFoco ? IconButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    segmentedButtonTheme: realceFoco ? SegmentedButtonThemeData(style: _focoBotao(_bordaFoco)) : null,
    // o mesmo objeto nos dois temas: o ChipThemeData.lerp falha com um side que resolve a null
    // (só não interpola se for idêntico); o resolvedor já vê o modo de realce
    chipTheme: _temaChips,
    tabBarTheme: TabBarThemeData(
      overlayColor: realceFoco ? _seFocado(_fundoFoco) : null,
      dividerColor: Colors.transparent,
      labelColor: Tokens.texto,
      unselectedLabelColor: Tokens.texto2,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: Tokens.acento2, width: 3),
        borderRadius: BorderRadius.all(Radius.circular(3)),
        insets: EdgeInsets.symmetric(horizontal: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.vidro,
      isDense: true,
      hintStyle: const TextStyle(color: Tokens.texto2),
      prefixIconColor: Tokens.texto2,
      border: bordaCampo,
      enabledBorder: bordaCampo,
      focusedBorder: realceFoco
          ? const OutlineInputBorder(borderRadius: raioCampo, borderSide: _bordaFoco)
          : const OutlineInputBorder(borderRadius: raioCampo, borderSide: BorderSide(color: Tokens.acento, width: 1.5)),
    ),
  );
}

const _bordaFoco = Realce.borda;
final _temaChips = ChipThemeData(
  side: WidgetStateBorderSide.resolveWith(
      (s) => _focoVisivel(s) ? _bordaFoco : const BorderSide(color: Tokens.bordaVidro)),
  backgroundColor: Tokens.vidro,
  selectedColor: const Color(0x4D6C7BFF),
  checkmarkColor: Tokens.texto,
  labelStyle: const TextStyle(fontWeight: FontWeight.w600, color: Tokens.texto),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Tokens.raioCampo))),
);
const _bordaFocoClara = Realce.bordaClara;
final _fundoFoco = Realce.fundo;

/// O fundo dos botões principais: o gradiente índigo→violeta (mais claro com o rato/foco/toque);
/// desligado, vidro.
Widget _fundoGradiente(BuildContext context, Set<WidgetState> s, Widget? filho) {
  if (s.contains(WidgetState.disabled)) {
    return DecoratedBox(decoration: const BoxDecoration(color: Tokens.vidroForte), child: filho);
  }
  final claro = s.contains(WidgetState.pressed)
      ? .22
      : (s.contains(WidgetState.hovered) || _focoVisivel(s) ? .12 : 0.0);
  final cores = [
    for (final c in Tokens.gradienteAcento.colors) Color.lerp(c, Colors.white, claro)!,
  ];
  return DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: cores)), child: filho);
}

/// `v` só no estado focado e com o realce do teclado/comando (no telemóvel ou com o rato, um
/// botão com foco automático não ganha borda); nos outros casos fica o valor por omissão.
bool _focoVisivel(Set<WidgetState> s) =>
    s.contains(WidgetState.focused) && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

WidgetStateProperty<T?> _seFocado<T>(T v) => WidgetStateProperty.resolveWith((s) => _focoVisivel(s) ? v : null);

ButtonStyle _focoBotao(BorderSide borda) => ButtonStyle(side: _seFocado(borda), overlayColor: _seFocado(_fundoFoco));

/// Botões de contorno/texto: cantos de 14; com o comando, a borda de realce no foco.
ButtonStyle _estiloBotao(bool realceFoco, {BorderSide? lado}) => ButtonStyle(
      shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Tokens.raioBotao)))),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      side: WidgetStateProperty.resolveWith((s) => realceFoco && _focoVisivel(s) ? _bordaFoco : lado),
      overlayColor: realceFoco ? _seFocado(_fundoFoco) : null,
    );

/// Cor e texto de um estado da verificação.
(Color, String, IconData) visualEstado(String? estado) => switch (estado) {
      'funciona' => (Tokens.ok, 'Funciona', Icons.check_circle_outline),
      'nao_funciona' => (Tokens.mau, 'Não funciona', Icons.cancel_outlined),
      'inconclusivo' => (Tokens.aviso, 'Inconclusivo', Icons.warning_amber_rounded),
      _ => (Tokens.neutro, 'Por verificar', Icons.help_outline),
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
