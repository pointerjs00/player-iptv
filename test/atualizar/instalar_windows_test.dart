import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/atualizar/descarregar.dart';
import 'package:player_iptv/atualizar/instalar_windows.dart';

/// Atualizar no Windows: extrair o zip, o script que troca os ficheiros depois de a app fechar,
/// e a pasta da app tem de ser gravável.
void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('instalar_windows'));
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  File zipCom(Map<String, String> ficheiros) {
    final a = Archive();
    ficheiros.forEach((nome, texto) => a.addFile(ArchiveFile.bytes(nome, utf8.encode(texto))));
    final f = File('${pasta.path}${Platform.pathSeparator}pacote.zip')..writeAsBytesSync(ZipEncoder().encode(a));
    return f;
  }

  test('extrairZip devolve a pasta TVIntel com o exe', () async {
    final zip = zipCom({'TVIntel/TVIntel.exe': 'exe', 'TVIntel/data/app.so': 'so'});
    final destino = Directory('${pasta.path}${Platform.pathSeparator}extraido');
    final app = await extrairZip(zip, destino);
    expect(app.path, endsWith('TVIntel'));
    expect(File('${app.path}${Platform.pathSeparator}TVIntel.exe').readAsStringSync(), 'exe');
    expect(File('${app.path}${Platform.pathSeparator}data${Platform.pathSeparator}app.so').existsSync(), isTrue);
  });

  test('extrairZip sem TVIntel/TVIntel.exe: ErroPacote', () async {
    final zip = zipCom({'outra/coisa.txt': 'x'});
    await expectLater(
        extrairZip(zip, Directory('${pasta.path}${Platform.pathSeparator}x')), throwsA(isA<ErroPacote>()));
  });

  test('o script espera a app fechar, copia, volta a abrir e aguenta caminhos com espaços e apóstrofos', () {
    final s = scriptTroca(
        pid: 4321,
        origem: r"C:\Users\O'Neil\AppData\Local\Temp\TVIntel-atualizar\TVIntel",
        destino: r"C:\Users\O'Neil\Ambiente de trabalho\TVIntel",
        exe: r"C:\Users\O'Neil\Ambiente de trabalho\TVIntel\TVIntel.exe");
    expect(s, contains('Wait-Process -Id 4321'));
    expect(s, contains(r"'C:\Users\O''Neil\AppData\Local\Temp\TVIntel-atualizar\TVIntel'"), reason: "o ' duplicado");
    expect(s, contains(r"'C:\Users\O''Neil\Ambiente de trabalho\TVIntel'"));
    expect(s, contains('robocopy'));
    expect(s, contains('Start-Process'));
    expect(s, isNot(contains(r"O'Neil")), reason: "nenhum ' sozinho dentro das strings");
    final copiar = s.indexOf('robocopy'), abrir = s.indexOf('Start-Process');
    expect(s.indexOf('Wait-Process'), lessThan(copiar));
    expect(copiar, lessThan(abrir));
  });

  test('o script espera por todos os processos da pasta da app (a janela do player é outro) e não copia se ficarem abertos', () {
    final s = scriptTroca(pid: 1, origem: r'C:\t\extraido\TVIntel', destino: r'D:\Apps\TVIntel', exe: r'D:\Apps\TVIntel\TVIntel.exe');
    expect(s, contains('Get-Process'));
    expect(s, contains('StartsWith('), reason: 'os processos cujo executável está dentro da pasta da app');
    final esperar = s.indexOf('Get-Process'), copiar = s.indexOf(r'robocopy $origem $destino');
    expect(esperar, lessThan(copiar));
    expect(s.substring(esperar, copiar), contains('exit'), reason: 'ainda abertos: sai sem copiar nada');
  });

  test('o script guarda a versão anterior antes de copiar e repõe-na se a cópia falhar', () {
    final s = scriptTroca(pid: 1, origem: r'C:\t\extraido\TVIntel', destino: r'D:\Apps\TVIntel', exe: r'D:\Apps\TVIntel\TVIntel.exe');
    final guardar = s.indexOf(r'robocopy $destino $anterior');
    final copiar = s.indexOf(r'robocopy $origem $destino');
    final repor = s.indexOf(r'robocopy $anterior $destino');
    expect(guardar, greaterThan(0));
    expect(guardar, lessThan(copiar));
    expect(copiar, lessThan(repor));
    expect(s.lastIndexOf('Start-Process'), greaterThan(repor), reason: 'abre a app no fim, reposta ou nova');
  });

  test('app na raiz de uma unidade (E:\\): o robocopy recebe «E:\\.» (com «E:\\» lia a aspa como escapada)', () {
    final s = scriptTroca(pid: 1, origem: r'C:\t\extraido\TVIntel', destino: r'E:\', exe: r'E:\TVIntel.exe');
    expect(s, contains(r"$destino = 'E:\.'"));
    expect(s, contains(r"$prefixo = 'E:\'"), reason: 'os processos da unidade, para esperar por eles');
  });

  test('o script marca logo que arrancou (a app só fecha depois de o ver)', () {
    final s = scriptTroca(
        pid: 1, origem: r'C:\t\extraido\TVIntel', destino: r'D:\Apps\TVIntel', exe: r'D:\Apps\TVIntel\TVIntel.exe', marca: r'C:\t\iniciado');
    final marcar = s.indexOf(r"'C:\t\iniciado'");
    expect(marcar, greaterThan(0));
    expect(marcar, lessThan(s.indexOf('Wait-Process')));
  });

  test('correu bem: o script apaga a pasta temporária e a si próprio (o registo fica só se falhar)', () {
    final s = scriptTroca(pid: 1, origem: r'C:\t\extraido\TVIntel', destino: r'D:\Apps\TVIntel', exe: r'D:\Apps\TVIntel\TVIntel.exe');
    final fim = s.substring(s.lastIndexOf('Start-Process'));
    expect(fim, contains(r'Remove-Item -LiteralPath $pasta -Recurse -Force'));
    expect(fim, contains(r'$PSCommandPath'));
  });

  test('instalarWindows: se o script não arrancar (antivírus), não fecha a app e dá erro', () async {
    final zip = zipCom({'TVIntel/TVIntel.exe': 'exe novo'});
    var fechou = false;
    await expectLater(
        instalarWindows(zip,
            temp: Directory('${pasta.path}${Platform.pathSeparator}tmp'),
            exe: r'D:\Apps\TVIntel\TVIntel.exe',
            pid: 99,
            esperaMarca: const Duration(milliseconds: 300),
            iniciar: (exe, args) async {}, // nunca corre
            fechar: () async => fechou = true),
        throwsA(isA<ErroPacote>()));
    expect(fechou, isFalse);
  });

  test('pastaGravavel: true numa pasta temporária, false numa que não existe', () {
    expect(pastaGravavel(pasta), isTrue);
    expect(pasta.listSync(), isEmpty, reason: 'o ficheiro de teste é apagado');
    expect(pastaGravavel(Directory('${pasta.path}${Platform.pathSeparator}nao-existe')), isFalse);
  });

  test('instalarWindows: extrai, escreve o script, lança-o (desligado da app) e fecha a app', () async {
    final zip = zipCom({'TVIntel/TVIntel.exe': 'exe novo'});
    final lancados = <(String, List<String>)>[];
    var fechou = false;
    await instalarWindows(zip,
        temp: Directory('${pasta.path}${Platform.pathSeparator}tmp'),
        exe: r'D:\Apps\TVIntel\TVIntel.exe',
        pid: 99,
        iniciar: (exe, args) async {
          lancados.add((exe, args));
          // o script arranca: a primeira coisa que faz é a marca
          File('${pasta.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}iniciado').writeAsStringSync('ok');
        },
        fechar: () async => fechou = true);
    expect(lancados.single.$1, 'powershell');
    final script = File(lancados.single.$2.last);
    expect(script.existsSync(), isTrue);
    expect(script.readAsStringSync(), contains(r"'D:\Apps\TVIntel'"));
    expect(script.readAsStringSync(), contains('Wait-Process -Id 99'));
    expect(fechou, isTrue);
  });

  test('citarArgumento segue as regras do Windows (espaços, aspas, barras no fim)', () {
    expect(citarArgumento('-File'), '-File');
    expect(citarArgumento(r'C:\Área de O'"'"r'Neil\a.ps1'), r'"C:\Área de O'"'"r'Neil\a.ps1"');
    expect(citarArgumento(r'E:\ x\'), r'"E:\ x\\"');
    expect(citarArgumento('a"b'), r'"a\"b"');
    expect(citarArgumento(''), '""');
  });

  // De ponta a ponta, com o PowerShell verdadeiro: na 1.0.28 a app lançava-o em modo «detached»
  // (DETACHED_PROCESS, sem consola) e ele morria antes da primeira linha — a app fechava e não
  // voltava a abrir.
  test('instalarWindows com o lançador real: o script corre e troca os ficheiros', () async {
    final sep = Platform.pathSeparator;
    final app = Directory("${pasta.path}$sepÁrea de O'Neil${sep}TVIntel")..createSync(recursive: true);
    File('${app.path}${sep}TVIntel.exe').writeAsStringSync('exe velho');
    final zip = zipCom({'TVIntel/TVIntel.exe': 'exe novo', 'TVIntel/data/novo.txt': 'novo'});
    final saiu = await Process.start('cmd', ['/c', 'exit']); // um pid que já fechou: não há que esperar
    await saiu.exitCode;
    final temp = Directory('${pasta.path}${sep}tmp');
    var fechou = false;
    await instalarWindows(zip,
        temp: temp,
        exe: '${app.path}${sep}TVIntel.exe',
        pid: saiu.pid,
        esperaMarca: const Duration(seconds: 20),
        fechar: () async => fechou = true);
    expect(fechou, isTrue, reason: 'o script marcou que arrancou');
    final extraido = Directory('${temp.path}${sep}extraido');
    final fim = DateTime.now().add(const Duration(seconds: 30));
    while (extraido.existsSync() && DateTime.now().isBefore(fim)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(File('${app.path}${sep}TVIntel.exe').readAsStringSync(), 'exe novo');
    expect(File('${app.path}${sep}data${sep}novo.txt').existsSync(), isTrue);
    expect(extraido.existsSync(), isFalse, reason: 'correu bem: a pasta temporária foi apagada');
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(minutes: 2)));
}
