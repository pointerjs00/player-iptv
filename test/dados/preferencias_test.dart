import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/dados/preferencias.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

void main() {
  late Directory pasta;
  setUp(() => pasta = Directory.systemTemp.createTempSync('prefs'));
  tearDown(() => pasta.deleteSync(recursive: true));

  File ficheiro([String nome = 'preferencias.json']) => File('${pasta.path}${Platform.pathSeparator}$nome');

  test('sem ficheiro: desentrelaçamento ligado, Ajustar, hardware, volume 100, direto; taxa do ecrã só na TV',
      () async {
    final tv = await Preferencias.abrir(pasta, tv: true);
    expect(tv.desentrelacar, isTrue);
    expect(tv.formato, FormatoImagem.ajustar);
    expect(tv.hardware, isTrue);
    expect(tv.volume, 100);
    expect(tv.modoAndroid, ModoDescodificacao.direto);
    expect(tv.ajustarTaxaEcra, isTrue);
    final tele = await Preferencias.abrir(pasta);
    expect(tele.ajustarTaxaEcra, isFalse);
  });

  test('guarda e volta a ler todos os campos', () async {
    final p = await Preferencias.abrir(pasta, tv: true);
    p
      ..desentrelacar = false
      ..formato = FormatoImagem.r4x3
      ..hardware = false
      ..volume = 35
      ..modoAndroid = ModoDescodificacao.compativel
      ..ajustarTaxaEcra = false;
    await p.guardar();
    final q = await Preferencias.abrir(pasta, tv: true);
    expect(q.desentrelacar, isFalse);
    expect(q.formato, FormatoImagem.r4x3);
    expect(q.hardware, isFalse);
    expect(q.volume, 35);
    expect(q.modoAndroid, ModoDescodificacao.compativel);
    expect(q.ajustarTaxaEcra, isFalse);
  });

  test('a velocidade não é uma preferência (não vai para o ficheiro)', () async {
    final p = await Preferencias.abrir(pasta);
    await p.guardar();
    final m = jsonDecode(ficheiro().readAsStringSync()) as Map;
    expect(m.keys.where((k) => k.toString().contains('veloc')), isEmpty);
  });

  test('mudar um campo avisa quem ouve (ChangeNotifier); o mesmo valor não', () async {
    final p = await Preferencias.abrir(pasta);
    var avisos = 0;
    p.addListener(() => avisos++);
    p.formato = FormatoImagem.zoom;
    p.volume = 50;
    p.volume = 50;
    expect(avisos, 2);
  });

  test('volume fora de 0..100 fica nos limites', () async {
    final p = await Preferencias.abrir(pasta);
    p.volume = 140;
    expect(p.volume, 100);
    p.volume = -3;
    expect(p.volume, 0);
  });

  test('gravações seguidas não se atropelam (a última fica)', () async {
    final p = await Preferencias.abrir(pasta);
    final futuros = <Future<void>>[];
    for (var v = 0; v <= 20; v++) {
      p.volume = v.toDouble();
      futuros.add(p.guardar());
    }
    await Future.wait(futuros);
    expect((await Preferencias.abrir(pasta)).volume, 20);
  });

  test('migra o ficheiro antigo do player (preferencias_player.json)', () async {
    ficheiro('preferencias_player.json')
        .writeAsStringSync('{"modoAndroid": "compativel", "ajustarTaxaEcra": false}');
    final p = await Preferencias.abrir(pasta, tv: true);
    expect(p.modoAndroid, ModoDescodificacao.compativel);
    expect(p.ajustarTaxaEcra, isFalse);
    expect(p.desentrelacar, isTrue);
  });

  test('o ficheiro novo ganha ao antigo', () async {
    ficheiro('preferencias_player.json').writeAsStringSync('{"modoAndroid": "compativel"}');
    ficheiro().writeAsStringSync('{"modoAndroid": "direto"}');
    expect((await Preferencias.abrir(pasta)).modoAndroid, ModoDescodificacao.direto);
  });

  test('valores com o tipo errado: só esses ficam por omissão, .bak guardado, nunca exceção', () async {
    ficheiro().writeAsStringSync('{"desentrelacar": "sim", "formato": "zoom", "volume": "alto", "hardware": false}');
    final p = await Preferencias.abrir(pasta);
    expect(p.desentrelacar, isTrue);
    expect(p.formato, FormatoImagem.zoom);
    expect(p.volume, 100);
    expect(p.hardware, isFalse);
    expect(File('${ficheiro().path}.bak').readAsStringSync(), contains('"alto"'));
  });

  test('JSON estragado ou com outra forma: valores por omissão e .bak', () async {
    ficheiro().writeAsStringSync('[1, 2]');
    expect((await Preferencias.abrir(pasta)).formato, FormatoImagem.ajustar);
    expect(File('${ficheiro().path}.bak').existsSync(), isTrue);
    ficheiro().writeAsStringSync('{nao json');
    expect((await Preferencias.abrir(pasta)).desentrelacar, isTrue);
    expect(File('${ficheiro().path}.bak').readAsStringSync(), '{nao json');
  });

  test('bytes que não são UTF-8: valores por omissão', () async {
    ficheiro().writeAsBytesSync([0xff, 0xfe, 0x7b]);
    expect((await Preferencias.abrir(pasta)).volume, 100);
  });

  test('formato desconhecido: Ajustar', () async {
    ficheiro().writeAsStringSync('{"formato": "21:9"}');
    expect((await Preferencias.abrir(pasta)).formato, FormatoImagem.ajustar);
  });

  test('a pasta nem existe: valores por omissão; guardar não lança', () async {
    final p = await Preferencias.abrir(Directory('${pasta.path}${Platform.pathSeparator}nao_existe'), tv: true);
    expect(p.desentrelacar, isTrue);
    await p.guardar();
  });

  test('formatos de imagem: nomes e rótulos', () {
    expect(FormatoImagem.values.map((f) => f.rotulo),
        ['Ajustar', 'Preencher', 'Esticar', '16:9', '4:3', 'Zoom']);
    for (final f in FormatoImagem.values) {
      expect(FormatoImagem.deNome(f.nome), f);
    }
  });

  group('definições (Tarefa 7)', () {
    test('tempo limite da verificação: 8 s por omissão, entre 5 e 30, guardado', () async {
      final p = await Preferencias.abrir(pasta);
      expect(p.timeoutVerificacao, 8);
      p.timeoutVerificacao = 2;
      expect(p.timeoutVerificacao, 5);
      p.timeoutVerificacao = 99;
      expect(p.timeoutVerificacao, 30);
      p.timeoutVerificacao = 20;
      await p.guardar();
      expect((await Preferencias.abrir(pasta)).timeoutVerificacao, 20);
    });

    test('user-agent personalizado: vazio por omissão, aparado, sem quebras de linha, guardado', () async {
      final p = await Preferencias.abrir(pasta);
      expect(p.userAgent, '');
      p.userAgent = '  MeuPlayer/1.0${String.fromCharCodes([13, 10])}X-Falso: 1  ';
      expect(p.userAgent, 'MeuPlayer/1.0X-Falso: 1');
      p.userAgent = 'MeuPlayer/1.0';
      await p.guardar();
      expect((await Preferencias.abrir(pasta)).userAgent, 'MeuPlayer/1.0');
    });

    test('duas janelas: cada uma grava só o que mudou e a outra não perde nada', () async {
      final principal = await Preferencias.abrir(pasta);
      final janela = await Preferencias.abrir(pasta);
      principal.userAgent = 'UA-principal';
      janela.volume = 40;
      await Future.wait([principal.guardar(), janela.guardar()]);
      final lido = await Preferencias.abrir(pasta);
      expect(lido.userAgent, 'UA-principal');
      expect(lido.volume, 40);
      // a gravação seguinte da janela não repõe o que ela não mudou
      janela.volume = 30;
      await janela.guardar();
      expect((await Preferencias.abrir(pasta)).userAgent, 'UA-principal');
    });

    test('chaves desconhecidas do ficheiro (outra versão) não se perdem ao gravar', () async {
      ficheiro().writeAsStringSync('{"futura": 7}');
      final p = await Preferencias.abrir(pasta);
      p.volume = 10;
      await p.guardar();
      expect(jsonDecode(ficheiro().readAsStringSync())['futura'], 7);
    });

    test('recarregar apanha o que outra janela gravou, sem perder alterações por gravar', () async {
      final principal = await Preferencias.abrir(pasta);
      final janela = await Preferencias.abrir(pasta);
      principal.formato = FormatoImagem.zoom;
      principal.timeoutVerificacao = 25;
      await principal.guardar();
      janela.volume = 12; // por gravar
      await janela.recarregar();
      expect(janela.formato, FormatoImagem.zoom);
      expect(janela.timeoutVerificacao, 25);
      expect(janela.volume, 12);
    });

    test('o ficheiro temporário é único por gravação (nenhum fica para trás)', () async {
      final p = await Preferencias.abrir(pasta);
      await Future.wait([for (var v = 0; v < 8; v++) (p..volume = v.toDouble()).guardar()]);
      expect(pasta.listSync().map((e) => e.path).where((c) => c.endsWith('.tmp')), isEmpty);
    });

    test('aplicar: só as chaves válidas do mapa mudam e ficam por gravar', () async {
      final p = await Preferencias.abrir(pasta);
      p.aplicar({'volume': 20, 'formato': 'zoom', 'hardware': 'nao', 'userAgent': 'X/1'});
      expect((p.volume, p.formato, p.hardware, p.userAgent), (20.0, FormatoImagem.zoom, true, 'X/1'));
      await p.guardar();
      expect((await Preferencias.abrir(pasta)).userAgent, 'X/1');
    });

    test('I3: a gravação espera pelo bloqueio do ficheiro (outra janela a gravar) e só depois escreve', () async {
      final p = await Preferencias.abrir(pasta);
      final lock = File('${pasta.path}${Platform.pathSeparator}preferencias.lock').openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      p.volume = 12;
      var feito = false;
      final f = p.guardar().then((_) => feito = true);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(feito, isFalse, reason: 'a outra janela tem o bloqueio');
      lock.unlockSync();
      lock.closeSync();
      await f;
      expect((await Preferencias.abrir(pasta)).volume, 12);
    });

    test('I3: sem conseguir o bloqueio a tempo, falha e as chaves continuam por gravar (nunca "gravadas")', () async {
      final p = await Preferencias.abrir(pasta);
      final antes = Preferencias.esperaBloqueio;
      Preferencias.esperaBloqueio = const Duration(milliseconds: 300);
      addTearDown(() => Preferencias.esperaBloqueio = antes);
      final lock = File('${pasta.path}${Platform.pathSeparator}preferencias.lock').openSync(mode: FileMode.append)
        ..lockSync(FileLock.exclusive);
      p.volume = 7;
      await expectLater(p.guardar(), throwsA(isA<FileSystemException>()));
      expect(ficheiro().existsSync(), isFalse);
      lock.unlockSync();
      lock.closeSync();
      await p.guardar(); // volta a tentar a mesma chave
      expect((await Preferencias.abrir(pasta)).volume, 7);
    });

    test('I3: gravações alternadas de duas janelas nunca perdem uma atualização', () async {
      final a = await Preferencias.abrir(pasta);
      final b = await Preferencias.abrir(pasta);
      for (var i = 1; i <= 12; i++) {
        a.timeoutVerificacao = 5 + i;
        b.volume = i.toDouble();
        await Future.wait([a.guardar(), b.guardar()]);
        final lido = await Preferencias.abrir(pasta);
        expect((lido.timeoutVerificacao, lido.volume), (5 + i, i.toDouble()), reason: 'volta $i');
      }
    });

    test('I4: ficheiro estragado a meio da vida: grava o estado completo e guarda um .bak', () async {
      ficheiro().writeAsStringSync('{"formato": "zoom", "volume": 40}');
      final p = await Preferencias.abrir(pasta);
      ficheiro().writeAsStringSync('{lixo');
      p.userAgent = 'X/1';
      await p.guardar();
      final m = jsonDecode(ficheiro().readAsStringSync()) as Map;
      expect(m['formato'], 'zoom');
      expect(m['volume'], 40);
      expect(m['userAgent'], 'X/1');
      expect(File('${ficheiro().path}.bak').readAsStringSync(), '{lixo');
    });
  });

  group('modo de desentrelaçamento (Automático / Ligado / Desligado)', () {
    test('por omissão: Automático (o "desentrelacar" antigo continua a dar true)', () async {
      final p = await Preferencias.abrir(pasta);
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.automatico);
      expect(p.desentrelacar, isTrue);
    });

    test('ficheiro antigo: desentrelacar true -> Automático, false -> Desligado', () async {
      ficheiro().writeAsStringSync('{"desentrelacar": true}');
      expect((await Preferencias.abrir(pasta)).modoDesentrelacamento, ModoDesentrelacamento.automatico);
      ficheiro().writeAsStringSync('{"desentrelacar": false}');
      final p = await Preferencias.abrir(pasta);
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.desligado);
      expect(p.desentrelacar, isFalse);
    });

    test('grava "modo_desentrelacamento" (e o "desentrelacar" para as versões anteriores) e volta a ler', () async {
      final p = await Preferencias.abrir(pasta)..modoDesentrelacamento = ModoDesentrelacamento.ligado;
      await p.guardar();
      final m = jsonDecode(ficheiro().readAsStringSync()) as Map;
      expect(m['modo_desentrelacamento'], 'ligado');
      expect(m['desentrelacar'], isTrue);
      expect((await Preferencias.abrir(pasta)).modoDesentrelacamento, ModoDesentrelacamento.ligado);
    });

    test('o modo novo ganha ao "desentrelacar"; um modo desconhecido cai no antigo', () async {
      ficheiro().writeAsStringSync('{"modo_desentrelacamento": "ligado", "desentrelacar": false}');
      expect((await Preferencias.abrir(pasta)).modoDesentrelacamento, ModoDesentrelacamento.ligado);
      ficheiro().writeAsStringSync('{"modo_desentrelacamento": "talvez", "desentrelacar": false}');
      expect((await Preferencias.abrir(pasta)).modoDesentrelacamento, ModoDesentrelacamento.desligado);
    });

    test('o interruptor das Definições (bool): ligar dá Automático, desligar Desligado; Ligado fica Ligado', () {
      final p = Preferencias.omissao()..desentrelacar = false;
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.desligado);
      p.desentrelacar = true;
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.automatico);
      p
        ..modoDesentrelacamento = ModoDesentrelacamento.ligado
        ..desentrelacar = true;
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.ligado);
    });

    test('aplicar (cópia de segurança antiga, só com "desentrelacar")', () {
      final p = Preferencias.omissao()..aplicar({'desentrelacar': false});
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.desligado);
      p.aplicar({'modo_desentrelacamento': 'ligado'});
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.ligado);
      p.aplicar({'volume': 10});
      expect(p.modoDesentrelacamento, ModoDesentrelacamento.ligado, reason: 'sem as chaves não muda');
    });

    test('nomes e rótulos', () {
      expect(ModoDesentrelacamento.values.map((m) => m.rotulo), ['Automático', 'Ligado', 'Desligado']);
      for (final m in ModoDesentrelacamento.values) {
        expect(ModoDesentrelacamento.deNome(m.nome), m);
      }
    });
  });
}
