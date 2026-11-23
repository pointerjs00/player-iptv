/// A edição da app, escolhida na compilação.
///
/// A edição de partilha (`--dart-define=PARTILHA=true`) não tem a pesquisa de listas no blog do
/// stbstalker. Como [edicaoPartilha] é constante, o compilador deita fora o código que ela desliga:
/// a pesquisa e o endereço do blog nem chegam ao pacote.
const edicaoPartilha = bool.fromEnvironment('PARTILHA');
