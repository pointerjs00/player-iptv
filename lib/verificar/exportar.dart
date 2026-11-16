/// Exportar listas: Accounts.json (sfvip player) ou ficheiros .ini (Stalker Portal Player) num
/// zip. Os nomes seguem NNNHOST DDMMAA, com INC à frente nas inconclusivas.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../dados/biblioteca.dart';
import '../modelo/conta.dart';

Map<String, dynamic> _dict(Lista l) => {...contaParaDict(l.conta), 'Name': l.nomeMostrado};

Uint8List exportarAccountsJson(Iterable<Lista> listas) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert([for (final l in listas) _dict(l)])));

/// Um .ini por lista Stalker; devolve (zip, nº de listas ignoradas por não terem MAC).
(Uint8List?, int) exportarZipIni(Iterable<Lista> listas) {
  final arq = Archive();
  final nomes = <String>{};
  var ignoradas = 0;
  for (final l in listas) {
    if (l.conta.tipo != Tipo.stalker || l.conta.mac.isEmpty) {
      ignoradas++;
      continue;
    }
    final base = l.nomeMostrado.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    var nome = base;
    for (var k = 2; !nomes.add(nome.toLowerCase()); k++) {
      nome = '$base ($k)';
    }
    final corpo = utf8.encode('[DNS]\r\nAddress=${l.conta.endereco}\r\nMac=${l.conta.mac}\r\n');
    arq.addFile(ArchiveFile('$nome.ini', corpo.length, corpo));
  }
  if (arq.isEmpty) return (null, ignoradas);
  return (Uint8List.fromList(ZipEncoder().encode(arq)), ignoradas);
}
