import 'package:material_ui/material_ui.dart';

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

ThemeData temaApp() {
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
    // o foco tem de se ver bem na TV
    focusColor: Cores.acento.withValues(alpha: .25),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Cores.superficie2,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
  );
}

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
