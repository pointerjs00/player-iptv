import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/direto/armazem.dart';
import 'package:player_iptv/direto/espaco.dart';
import 'package:player_iptv/direto/sessao_direto.dart';

const _gb = 1 << 30, _mb = 1 << 20;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reservaPara', () {
    test('com espaço para a reserva e a margem de 1 GB, fica a reserva', () {
      expect(reservaPara(2 * _gb, 3 * _gb), 2 * _gb);
      expect(reservaPara(2 * _gb, 10 * _gb), 2 * _gb);
    });

    test('não se sabe o espaço (null): a reserva, sem margem', () {
      expect(reservaPara(3 * _gb, null), 3 * _gb);
    });

    test('pouco espaço: a reserva baixa para o que couber com a margem, em blocos inteiros', () {
      expect(reservaPara(2 * _gb, 2 * _gb), 1 * _gb);
      expect(reservaPara(2 * _gb, _gb + 700 * _mb), 688 * _mb, reason: '700 MiB em blocos de 16 MiB');
      expect(reservaPara(2 * _gb, _gb + 700 * _mb, tamanhoBloco: 64 * 1024), 700 * _mb);
    });

    test('o mínimo de 256 MiB: abaixo dele não se grava (null = memória)', () {
      expect(reservaPara(2 * _gb, _gb + 256 * _mb), 256 * _mb, reason: 'o mínimo ainda cabe');
      expect(reservaPara(2 * _gb, _gb + 255 * _mb), isNull);
      expect(reservaPara(2 * _gb, 500 * _mb), isNull);
      expect(reservaPara(2 * _gb, 0), isNull);
    });
  });

  group('espacoLivre', () {
    test('Android: pelo canal player_iptv/ficheiros (espacoLivre) com a pasta que existe', () async {
      const canal = MethodChannel('player_iptv/ficheiros');
      final pedidos = <MethodCall>[];
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(canal, (c) async {
        pedidos.add(c);
        return 5 * _gb;
      });
      addTearDown(() => m.setMockMethodCallHandler(canal, null));
      final tmp = Directory.systemTemp.createTempSync('espaco_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final livre = await espacoLivre(Directory('${tmp.path}/direto/s1'), plataforma: PlataformaEspaco.android);
      expect(livre, 5 * _gb);
      expect(pedidos.single.method, 'espacoLivre');
      expect((pedidos.single.arguments as Map)['pasta'], tmp.path, reason: 'a primeira pasta que existe');
    });

    test('Android: um erro do canal dá null (não se sabe)', () async {
      const canal = MethodChannel('player_iptv/ficheiros');
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(canal, (c) async => throw PlatformException(code: 'io'));
      addTearDown(() => m.setMockMethodCallHandler(canal, null));
      expect(await espacoLivre(Directory.systemTemp, plataforma: PlataformaEspaco.android), isNull);
    });

    test('outros sistemas: null', () async {
      expect(await espacoLivre(Directory.systemTemp, plataforma: PlataformaEspaco.outro), isNull);
    });

    test('Windows: GetDiskFreeSpaceExW dá um número positivo', () async {
      final livre = await espacoLivre(Directory('${Directory.systemTemp.path}\\nao_existe\\x'));
      expect(livre, isNotNull);
      expect(livre, greaterThan(0));
    }, skip: !Platform.isWindows);
  });

  group('limparDireto (arranque)', () {
    test('apaga a pasta direto/ inteira e deixa o resto da cache', () async {
      final cache = Directory.systemTemp.createTempSync('cache_');
      addTearDown(() => cache.deleteSync(recursive: true));
      final sessao = Directory('${cache.path}/direto/s1_abc')..createSync(recursive: true);
      File('${sessao.path}/bloco_0.ts').writeAsBytesSync(List.filled(1000, 0x47));
      Directory('${cache.path}/direto/s2_def').createSync();
      final outro = File('${cache.path}/outro.txt')..writeAsStringSync('fica');
      await limparDireto(cache: cache);
      expect(Directory('${cache.path}/direto').existsSync(), isFalse);
      expect(outro.existsSync(), isTrue);
    });

    test('salta a sessão viva de outro processo (o bloqueio dela não se consegue) e apaga as outras',
        () async {
      final cache = Directory.systemTemp.createTempSync('cache_');
      addTearDown(() => cache.deleteSync(recursive: true));
      // a outra janela do player a gravar: a pasta dela com o bloqueio tomado (outro handle; no
      // Windows o bloqueio é por handle, como seria noutro processo)
      final viva = Directory('${cache.path}/direto/s_viva')..createSync(recursive: true);
      File('${viva.path}/bloco_0.ts').writeAsBytesSync(List.filled(100, 0x47));
      final bloqueio = File('${viva.path}/${ArmazemDisco.nomeBloqueio}').openSync(mode: FileMode.write)
        ..lockSync(FileLock.exclusive);
      // uma sobra com o bloqueio largado (o processo morreu) e outra sem bloqueio nenhum
      final morta = Directory('${cache.path}/direto/s_morta')..createSync();
      File('${morta.path}/${ArmazemDisco.nomeBloqueio}').writeAsStringSync('');
      final antiga = Directory('${cache.path}/direto/s_antiga')..createSync();
      await limparDireto(cache: cache);
      expect(viva.existsSync(), isTrue);
      expect(File('${viva.path}/bloco_0.ts').existsSync(), isTrue);
      expect(morta.existsSync(), isFalse);
      expect(antiga.existsSync(), isFalse);
      bloqueio.closeSync();
    }, skip: Platform.isWindows ? false : 'o bloqueio de ficheiros é por processo fora do Windows');

    test('uma sessão gravada viva (o seu bloqueio) não é apagada pela limpeza', () async {
      final cache = Directory.systemTemp.createTempSync('cache_');
      addTearDown(() => cache.deleteSync(recursive: true));
      final pasta = Directory('${cache.path}/direto/s1');
      final a = ArmazemDisco(pasta);
      await a.preparar();
      await a.abrir(0);
      await a.escrever([1, 2, 3], 0, 3);
      await limparDireto(cache: cache);
      expect(pasta.existsSync(), isTrue);
      await a.fechar(apagar: false);
      await limparDireto(cache: cache);
      expect(pasta.existsSync(), isFalse, reason: 'o bloqueio largado: é uma sobra');
    }, skip: Platform.isWindows ? false : 'o bloqueio de ficheiros é por processo fora do Windows');

    test('sem a pasta direto/ não faz nada (e nunca lança)', () async {
      final cache = Directory.systemTemp.createTempSync('cache_');
      addTearDown(() => cache.deleteSync(recursive: true));
      await limparDireto(cache: cache);
      await limparDireto(cache: Directory('${cache.path}/nao_existe'));
    });
  });
}
