import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../marca.dart';

/// A pasta das listas e das preferências. No Windows o path_provider forma-a com o ProductName
/// do executável (%APPDATA%\pt.playeriptv\<ProductName>): com o nome novo seria uma pasta vazia,
/// por isso a do nome antigo passa para lá (uma vez, se a nova ainda estiver vazia).
Future<Directory> pastaDados() async {
  final pasta = await getApplicationSupportDirectory();
  if (Platform.isWindows) await migrarPastaAntiga(pasta);
  return pasta;
}

/// Se `pasta` está vazia e ao lado há a do nome antigo, move-a para cá. Nunca lança: se não
/// consegue (a pasta antiga em uso), fica-se com a nova.
Future<void> migrarPastaAntiga(Directory pasta, {String antigo = nomeAppAntigo}) async {
  try {
    final velha = Directory('${pasta.parent.path}${Platform.pathSeparator}$antigo');
    if (velha.path == pasta.path || !await velha.exists()) return;
    if (await pasta.exists()) {
      if (!await pasta.list().isEmpty) return; // já tem dados: não se mexe
      await pasta.delete();
    }
    await velha.rename(pasta.path);
  } on FileSystemException {
    await pasta.create(recursive: true);
  }
}
