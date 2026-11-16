import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/rede/http.dart';
import 'package:player_iptv/verificar/estado.dart';
import 'package:player_iptv/verificar/exportar.dart';
import 'package:player_iptv/verificar/servico.dart';
import 'package:player_iptv/verificar/verificador.dart';

/// Verificador falso: devolve o estado pedido para cada host e conta quantas correm juntas.
class _Falso extends Verificador {
  _Falso(this.estados);
  final Map<String, EstadoV> estados;
  int aCorrer = 0, pico = 0;
  final soltar = Completer<void>();
  bool esperar = false;

  @override
  Future<ResultadoVerificacao> verificar(Conta conta, List<String> canaisTeste,
      {Duration timeout = const Duration(seconds: 8), Cancelamento? cancelamento, void Function(String)? aviso}) async {
    aCorrer++;
    if (aCorrer > pico) pico = aCorrer;
    aviso?.call('a testar ${canaisTeste.join('+')}');
    if (esperar) await soltar.future;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    aCorrer--;
    cancelamento?.verificar();
    return ResultadoVerificacao(estados[hostDe(conta.endereco)] ?? EstadoV.inconclusivo, 'falso',
        validade: '2027-10-16');
  }
}

void main() {
  late Directory pasta;
  late Biblioteca bib;
  setUp(() async {
    pasta = Directory.systemTemp.createTempSync('exp');
    bib = await Biblioteca.abrir(pasta);
    await bib.adicionar([
      Importada(contaDeLinha('http://nxtbox.uk/c/ 00:1A:79:00:00:01')!,
          UltimaVerificacao(estado: 'funciona', data: DateTime(2026), validade: '2027-10-16')),
      Importada(contaDeLinha('http://outro.com/c/ 00:1A:79:00:00:02')!,
          UltimaVerificacao(estado: 'inconclusivo', data: DateTime(2026))),
      Importada(contaDeLinha('http://xt.com:8080/get.php?username=u&password=p')!),
    ]);
  });
  tearDown(() {
    try {
      pasta.deleteSync(recursive: true);
    } on FileSystemException {/* Windows */}
  });

  test('Accounts.json com os nomes das listas e INC', () {
    final d = jsonDecode(utf8.decode(exportarAccountsJson(bib.listas))) as List;
    expect(d.map((e) => e['Name']), ['001NXTBOX 161027', 'INC 002OUTRO', '003XT']);
    expect(d.first['Mac'], '00:1A:79:00:00:01');
    expect(d.last['Username'], 'u');
  });

  test('zip de .ini só com as Stalker', () {
    final (zip, ignoradas) = exportarZipIni(bib.listas);
    expect(ignoradas, 1);
    final arq = ZipDecoder().decodeBytes(zip!);
    expect(arq.files.map((f) => f.name), ['001NXTBOX 161027.ini', 'INC 002OUTRO.ini']);
    expect(utf8.decode(arq.files.first.content as List<int>),
        '[DNS]\r\nAddress=http://nxtbox.uk/c/\r\nMac=00:1A:79:00:00:01\r\n');
    expect(exportarZipIni([bib.listas.last]), (null, 1));
  });

  test('serviço: no máximo N ao mesmo tempo, guarda os resultados e usa os canais de teste', () async {
    final f = _Falso({'nxtbox.uk': EstadoV.naoFunciona, 'outro.com': EstadoV.funciona});
    await bib.definirCanaisTeste(['rtp1', 'dazn1']);
    final s = ServicoVerificacao(bib, verificador: f, workers: 2);
    final avisos = <String>[];
    s.addListener(() => avisos.addAll(s.passos.values));
    await s.verificarVarias(bib.listas);
    expect(f.pico, 2);
    expect(bib.listas.map((l) => l.ultima!.estado), ['nao_funciona', 'funciona', 'inconclusivo']);
    expect(bib.listas[1].nome, '002OUTRO 161027');
    expect(avisos, contains('a testar rtp1+dazn1'));
    expect(s.ocupado, isFalse);
  });

  test('serviço: parar deixa o resultado anterior', () async {
    final f = _Falso({})..esperar = true;
    final s = ServicoVerificacao(bib, verificador: f, workers: 1);
    final fim = s.verificarVarias(bib.listas);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.passos.values, contains('na fila'));
    s.parar();
    f.soltar.complete();
    await fim;
    expect(bib.listas.first.ultima!.estado, 'funciona');
    expect(bib.listas.last.ultima, isNull);
  });
}
