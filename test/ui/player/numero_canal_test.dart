import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/modelo/canal.dart';
import 'package:player_iptv/ui/player/maquina_controlos.dart';
import 'package:player_iptv/ui/player/numero_canal.dart';

typedef K = LogicalKeyboardKey;

void main() {
  test('numeroMostrado: o do portal quando a lista os tem; senão a posição', () {
    const semNumeros = [Canal(id: 'a', nome: 'A', grupo: 'G'), Canal(id: 'b', nome: 'B', grupo: 'G')];
    const comNumeros = [Canal(id: 'a', nome: 'A', grupo: 'G', numero: 101), Canal(id: 'b', nome: 'B', grupo: 'G')];
    expect(numeroMostrado(semNumeros, 1), 2);
    expect(numeroMostrado(comNumeros, 0), 101);
    expect(numeroMostrado(comNumeros, 1), isNull, reason: 'sem número do portal: não se inventa a posição');
  });

  group('indicePorNumero', () {
    const semNumeros = [
      Canal(id: 'a', nome: 'A', grupo: 'G'),
      Canal(id: 'b', nome: 'B', grupo: 'G'),
      Canal(id: 'c', nome: 'C', grupo: 'G'),
    ];
    const comNumeros = [
      Canal(id: 'a', nome: 'A', grupo: 'G', numero: 101),
      Canal(id: 'b', nome: 'B', grupo: 'G', numero: 2),
      Canal(id: 'c', nome: 'C', grupo: 'G'),
    ];

    test('sem números do portal: a posição na lista (1 = o primeiro)', () {
      expect(indicePorNumero(semNumeros, 1), 0);
      expect(indicePorNumero(semNumeros, 3), 2);
      expect(indicePorNumero(semNumeros, 4), isNull);
      expect(indicePorNumero(semNumeros, 0), isNull);
    });

    test('com números do portal: o número do portal (não a posição)', () {
      expect(indicePorNumero(comNumeros, 101), 0);
      expect(indicePorNumero(comNumeros, 2), 1);
      expect(indicePorNumero(comNumeros, 3), isNull, reason: 'a posição 3 não conta quando há números');
    });
  });

  group('HistoricoCanais (alternar entre os dois últimos)', () {
    test('ir para outro guarda o anterior; alternar troca os dois', () {
      final h = HistoricoCanais(5);
      expect(h.alternar(), isNull, reason: 'ainda não há anterior');
      expect(h.irPara(9), 9);
      expect(h.alternar(), 5);
      expect(h.alternar(), 9);
      expect(h.atual, 9);
      expect(h.anterior, 5);
    });

    test('ir para o mesmo não muda nada; trocar de lista esquece o anterior', () {
      final h = HistoricoCanais(2);
      expect(h.irPara(2), isNull);
      expect(h.anterior, isNull);
      h.irPara(3);
      h.novaLista(0);
      expect(h.atual, 0);
      expect(h.anterior, isNull);
    });
  });

  group('MaquinaControlos: algarismos e alternar', () {
    test('algarismos (em cima e no teclado numérico) escrevem o número em qualquer vista', () {
      for (final v in VistaPlayer.values) {
        final m = MaquinaControlos()..vista = v;
        expect(m.tecla(K.digit1), AcaoPlayer.algarismo);
        expect(m.tecla(K.numpad2), AcaoPlayer.algarismo);
        expect(m.numero, '12');
        expect(m.vista, v, reason: 'os algarismos não abrem nem fecham a barra');
      }
    });

    test('no máximo 4 algarismos', () {
      final m = MaquinaControlos();
      for (final k in [K.digit1, K.digit2, K.digit3, K.digit4, K.digit5]) {
        m.tecla(k);
      }
      expect(m.numero, '1234');
    });

    test('com um número a meio: OK salta, Voltar cancela (não sai), Backspace apaga um', () {
      final m = MaquinaControlos();
      m.tecla(K.digit4);
      m.tecla(K.digit2);
      expect(m.tecla(K.backspace), AcaoPlayer.algarismo);
      expect(m.numero, '4');
      expect(m.tecla(K.select), AcaoPlayer.irParaNumero);
      expect(m.vista, VistaPlayer.escondida, reason: 'OK não mostrou a barra');
      expect(m.tirarNumero(), 4);
      expect(m.numero, '');

      m.tecla(K.digit7);
      expect(m.tecla(K.escape), AcaoPlayer.cancelarNumero);
      expect(m.numero, '');
      expect(m.tecla(K.escape), AcaoPlayer.sair);
    });

    test('Último canal (tecla do comando) e Backspace sem número alternam', () {
      final m = MaquinaControlos();
      expect(m.tecla(K.mediaLast), AcaoPlayer.alternarCanal);
      expect(m.tecla(K.backspace), AcaoPlayer.alternarCanal);
      m.vista = VistaPlayer.controlos;
      expect(m.tecla(K.mediaLast), AcaoPlayer.alternarCanal, reason: 'tecla própria: sempre');
    });

    test('as teclas que já existiam não mudam', () {
      final m = MaquinaControlos();
      expect(m.tecla(K.arrowUp), AcaoPlayer.canalSeguinte);
      expect(m.tecla(K.channelDown), AcaoPlayer.canalAnterior);
      expect(m.tecla(K.select), AcaoPlayer.mostrarControlos);
    });
  });
}
