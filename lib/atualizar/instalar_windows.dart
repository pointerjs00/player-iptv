/// Atualizar no Windows: um programa não se substitui enquanto está aberto. A app extrai a versão
/// nova para uma pasta temporária, deixa um script PowerShell a correr e fecha-se; o script espera
/// que ela feche, copia os ficheiros para a pasta do TVIntel.exe e volta a abri-la. Os dados
/// (AppData\Roaming) não são tocados.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

import '../idioma/idioma.dart';
import 'descarregar.dart' show ErroPacote;

/// A app pode escrever em `d`? (Em `C:\Program Files` não pode, sem ser administrador.)
bool pastaGravavel(Directory d) {
  final f = File('${d.path}${Platform.pathSeparator}.tvintel-escrita-$pid');
  try {
    f.writeAsStringSync('x', flush: true);
    f.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Extrai o zip da release para `destino` e devolve a pasta da app (`destino/TVIntel`).
Future<Directory> extrairZip(File zip, Directory destino) async {
  if (await destino.exists()) await destino.delete(recursive: true);
  await destino.create(recursive: true);
  // noutro isolate: descomprimir uns 70 MB no principal congelava a janela uns segundos
  final (de, para) = (zip.path, destino.path);
  await Isolate.run(() => extractFileToDisk(de, para));
  final sep = Platform.pathSeparator;
  final app = Directory('${destino.path}${sep}TVIntel');
  if (!await File('${app.path}${sep}TVIntel.exe').exists()) {
    throw ErroPacote(tr('o pacote do Windows não tem o TVIntel.exe'));
  }
  return app;
}

String _aspas(String s) => "'${s.replaceAll("'", "''")}'";

/// O script da troca:
/// 1. espera que a app (`pid`) feche e, depois, todos os processos que correm da pasta dela (a
///    janela do player é outro processo do mesmo exe e fecha uns segundos depois); se algum
///    continuar aberto ao fim de 60 s, sai sem tocar em nada;
/// 2. guarda a versão atual em `anterior` (ao lado de `origem`); se não conseguir, abre a app
///    como está e sai;
/// 3. copia a versão nova; se a cópia falhar (robocopy ≥ 8), repõe a anterior — ficheiros novos e
///    velhos misturados não arrancam;
/// 4. abre a app (nova, ou a anterior reposta); se correu bem, apaga a pasta temporária e o
///    próprio script.
/// O registo fica em `atualizar.log`, ao lado de `origem` (só fica se algo falhar). Com `marca`,
/// a primeira coisa que faz é criar esse ficheiro (a app só fecha depois de o ver).
String scriptTroca({
  required int pid,
  required String origem,
  required String destino,
  required String exe,
  String? marca,
}) {
  final semBarra = destino.replaceAll(RegExp(r'\\+$'), '');
  // «E:\» passado ao robocopy fica "E:\" e a barra escapa a aspa: «E:\.» é a mesma pasta
  final paraRobocopy = destino.endsWith('\\') ? '$destino.' : destino;
  return '''
\$ErrorActionPreference = 'SilentlyContinue'
${marca == null ? '' : "Set-Content -LiteralPath ${_aspas(marca)} -Value 'ok'"}
\$origem = ${_aspas(origem)}
\$destino = ${_aspas(paraRobocopy)}
\$exe = ${_aspas(exe)}
\$pasta = Split-Path -Parent \$origem
\$anterior = Join-Path \$pasta 'anterior'
\$registo = Join-Path \$pasta 'atualizar.log'
\$prefixo = ${_aspas('$semBarra\\')}
function Abertos { @(Get-Process | Where-Object { \$_.Path -and \$_.Path.StartsWith(\$prefixo, [StringComparison]::OrdinalIgnoreCase) }) }
Wait-Process -Id $pid -Timeout 60
\$fim = (Get-Date).AddSeconds(60)
while ((Abertos).Count -gt 0 -and (Get-Date) -lt \$fim) { Start-Sleep -Milliseconds 500 }
if ((Abertos).Count -gt 0) { 'A app continua aberta: nada foi copiado.' | Out-File -FilePath \$registo -Encoding utf8; exit }
Start-Sleep -Milliseconds 500
robocopy \$destino \$anterior /MIR /R:3 /W:1 /NFL /NDL /NJH /NP | Out-File -FilePath \$registo -Encoding utf8
if (\$LASTEXITCODE -ge 8) { 'Sem cópia da versão atual: nada foi trocado.' | Out-File -FilePath \$registo -Append -Encoding utf8; Start-Process -FilePath \$exe -WorkingDirectory \$destino; exit }
robocopy \$origem \$destino /E /R:10 /W:1 /NFL /NDL /NJH /NP | Out-File -FilePath \$registo -Append -Encoding utf8
\$codigo = \$LASTEXITCODE
if (\$codigo -ge 8) { robocopy \$anterior \$destino /E /R:30 /W:1 /NFL /NDL /NJH /NP | Out-File -FilePath \$registo -Append -Encoding utf8 }
Start-Process -FilePath \$exe -WorkingDirectory \$destino
if (\$codigo -lt 8) { Remove-Item -LiteralPath \$pasta -Recurse -Force; Remove-Item -LiteralPath \$PSCommandPath -Force }
''';
}

/// Prepara a troca e fecha a app: extrai `zip` para `<temp>/extraido`, escreve `<temp>/atualizar.ps1`,
/// lança-o desligado da app e, quando ele marca que arrancou (`<temp>/iniciado`), chama `fechar`.
/// Se a marca não aparecer em `esperaMarca` (antivírus, AppLocker), lança [ErroPacote] e a app
/// continua aberta como estava.
Future<void> instalarWindows(
  File zip, {
  required Future<void> Function() fechar,
  Directory? temp,
  String? exe,
  int? pid,
  Duration esperaMarca = const Duration(seconds: 10),
  Future<void> Function(String executavel, List<String> argumentos)? iniciar,
}) async {
  final sep = Platform.pathSeparator;
  final pasta = temp ?? Directory('${Directory.systemTemp.path}${sep}TVIntel-atualizar');
  await pasta.create(recursive: true);
  final app = await extrairZip(zip, Directory('${pasta.path}${sep}extraido'));
  try {
    await zip.delete();
  } on FileSystemException {
    /* fica na cache */
  }
  final executavel = exe ?? Platform.resolvedExecutable;
  final marca = File('${pasta.path}${sep}iniciado');
  if (await marca.exists()) await marca.delete();
  final script = File('${pasta.path}${sep}atualizar.ps1');
  // com BOM: o PowerShell 5.1 lê um UTF-8 sem BOM como ANSI (os acentos dos caminhos estragavam-se)
  await script.writeAsBytes([
    0xEF,
    0xBB,
    0xBF,
    ...utf8.encode(
      scriptTroca(
        pid: pid ?? _pidAtual(),
        origem: app.path,
        destino: File(executavel).parent.path,
        exe: executavel,
        marca: marca.path,
      ),
    ),
  ]);
  await (iniciar ?? _iniciar)('powershell', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    script.path,
  ]);
  // só se fecha a app quando o script já está a correr (senão ficava fechada e sem atualizar)
  final fim = DateTime.now().add(esperaMarca);
  while (!await marca.exists()) {
    if (DateTime.now().isAfter(fim)) {
      throw ErroPacote(tr('o Windows não deixou correr a atualização (antivírus?). A app continua como estava.'));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await fechar();
}

int _pidAtual() => pid;

Future<void> _iniciar(String executavel, List<String> argumentos) async {
  await Process.start(executavel, argumentos, mode: ProcessStartMode.detached);
}
