import 'package:flutter/widgets.dart';

import 'ingles.dart';

/// Os idiomas da app. O português é o original: os textos estão escritos em português no código
/// e [tr] troca-os pela tradução do idioma escolhido.
enum Idioma {
  pt('pt', 'Português', Locale('pt', 'PT')),
  en('en', 'English', Locale('en', 'US'));

  const Idioma(this.nome, this.rotulo, this.locale);

  /// O nome guardado nas preferências.
  final String nome;

  /// O nome do idioma, no próprio idioma (não se traduz).
  final String rotulo;

  /// O `Locale` do Material (datas, botões dos diálogos do sistema).
  final Locale locale;

  /// Um nome desconhecido dá o português (a omissão).
  static Idioma deNome(String? n) => values.firstWhere((i) => i.nome == n, orElse: () => pt);
}

/// O idioma da interface. Muda-se nas Definições (que o gravam nas preferências).
final idiomaApp = ValueNotifier<Idioma>(Idioma.pt);

/// O texto [pt] no idioma da app. `{0}`, `{1}`… trocam-se pelos [args] (na mesma ordem nos
/// dois idiomas). Sem tradução fica o português.
String tr(String pt, [List<Object?> args = const []]) {
  var s = idiomaApp.value == Idioma.en ? (textosIngles[pt] ?? pt) : pt;
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}

/// Reconstrói todos os widgets debaixo de [context] (sem perder o estado): ao mudar de idioma,
/// os textos voltam a passar por [tr].
void reconstruirTextos(BuildContext context) {
  void marcar(Element e) {
    e.markNeedsBuild();
    e.visitChildren(marcar);
  }

  (context as Element).visitChildren(marcar);
}
