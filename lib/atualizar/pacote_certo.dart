/// Qual dos ficheiros de uma release serve para este aparelho: a edição (completa ou partilha) e,
/// no Android, o processador; no Windows, o zip.
library;

import '../dados/nova_versao.dart';

enum Plataforma { android, windows, outra }

/// O fim do nome do APK de cada processador do Android (os que se publicam).
const _sufixoAbi = {'arm64-v8a': '-android-arm64.apk', 'armeabi-v7a': '-android-armv7.apk'};

/// O pacote para esta plataforma e edição; `abis` são as do aparelho, a preferida primeiro
/// (Build.SUPPORTED_ABIS). null: a release não tem nenhum que sirva.
Pacote? pacoteDaApp(List<Pacote> pacotes,
    {required Plataforma plataforma, List<String> abis = const [], required bool partilha}) {
  bool daEdicao(Pacote p) => p.nome.contains('-partilha-') == partilha;
  Pacote? acabadoEm(String sufixo) {
    for (final p in pacotes) {
      if (daEdicao(p) && p.nome.endsWith(sufixo)) return p;
    }
    return null;
  }

  switch (plataforma) {
    case Plataforma.android:
      for (final abi in abis) {
        final sufixo = _sufixoAbi[abi];
        final p = sufixo == null ? null : acabadoEm(sufixo);
        if (p != null) return p;
      }
      return null;
    case Plataforma.windows:
      return acabadoEm('-windows.zip');
    case Plataforma.outra:
      return null;
  }
}
