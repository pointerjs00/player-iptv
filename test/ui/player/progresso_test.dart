import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/progresso.dart';

String _cache({List<(double, double)> intervalos = const [], double? fim}) {
  final r = [for (final (a, b) in intervalos) '{"start":$a,"end":$b}'].join(',');
  return '{"seekable-ranges":[$r]${fim != null ? ',"cache-end":$fim' : ''},"bof-cached":false,"eof-cached":false}';
}

void main() {
  group('textoTempo (hh:mm:ss)', () {
    test('segundos, minutos e horas com dois algarismos', () {
      expect(textoTempo(Duration.zero), '00:00:00');
      expect(textoTempo(const Duration(seconds: 2)), '00:00:02');
      expect(textoTempo(const Duration(seconds: 30)), '00:00:30');
      expect(textoTempo(const Duration(minutes: 4, seconds: 5)), '00:04:05');
      expect(textoTempo(const Duration(hours: 1, minutes: 1, seconds: 1)), '01:01:01');
      expect(textoTempo(const Duration(hours: 123, seconds: 9)), '123:00:09');
    });

    test('corta as frações (não arredonda para cima) e nunca é negativo', () {
      expect(textoTempo(const Duration(milliseconds: 2999)), '00:00:02');
      expect(textoTempo(const Duration(seconds: -5)), '00:00:00');
    });

    test('desconhecido: traços', () {
      expect(textoTempo(null), '--:--:--');
    });
  });

  group('janelaDe', () {
    test('filme (seekable, duração conhecida): posição e duração; o buffer à frente pelo cache-end', () {
      final j = janelaDe({
        'time-pos': '2.4',
        'duration': '30.0',
        'seekable': 'yes',
        'partially-seekable': 'no',
        'demuxer-cache-state': _cache(intervalos: [(0, 12)], fim: 12),
      })!;
      expect(j.direto, isFalse);
      expect(j.inicio, 0);
      expect(j.fim, 30);
      expect(j.decorrido, const Duration(milliseconds: 2400));
      expect(j.total, const Duration(seconds: 30));
      expect(textoTempo(j.decorrido), '00:00:02');
      expect(textoTempo(j.total), '00:00:30');
      expect(j.fracao(j.posicao), closeTo(.08, 1e-9));
      expect(j.fracaoBuffer, closeTo(.4, 1e-9));
    });

    test('direto com buffer para trás: a janela vai do mais antigo no cache ao mais recente', () {
      // 40 s para trás (back buffer), a tocar a 100, recebido até 103
      final j = janelaDe({
        'time-pos': '100',
        'duration': '',
        'seekable': 'yes',
        'partially-seekable': 'yes',
        'demuxer-cache-state': _cache(intervalos: [(60, 103)], fim: 103),
      })!;
      expect(j.direto, isTrue);
      expect(j.inicio, 60);
      expect(j.fim, 103);
      expect(j.decorrido, const Duration(seconds: 40));
      expect(j.total, const Duration(seconds: 43));
      expect(j.fracao(100), closeTo(40 / 43, 1e-9));
      expect(j.fracaoBuffer, 1);
    });

    test('direto: o cache-end para lá do intervalo (readahead) alarga a janela', () {
      final j = janelaDe({
        'time-pos': '50',
        'seekable': 'no',
        'demuxer-cache-state': _cache(intervalos: [(45, 52)], fim: 55),
      })!;
      expect(j.direto, isTrue);
      expect((j.inicio, j.fim), (45.0, 55.0));
    });

    test('direto com vários intervalos: o que tem a posição (não o último)', () {
      final j = janelaDe({
        'time-pos': '20',
        'seekable': 'yes',
        'partially-seekable': 'yes',
        'demuxer-cache-state': _cache(intervalos: [(10, 25), (200, 230)], fim: 230),
      })!;
      expect((j.inicio, j.fim), (10.0, 25.0));
      expect(j.fracaoBuffer, 1);
    });

    test('duração desconhecida e sem intervalos: a janela é da posição ao fim do cache', () {
      final j = janelaDe({
        'time-pos': '7',
        'duration': '',
        'seekable': 'yes',
        'partially-seekable': 'yes',
        'demuxer-cache-state': _cache(fim: 9),
      })!;
      expect(j.direto, isTrue, reason: 'sem partially-seekable=no, é direto');
      expect((j.inicio, j.fim), (7.0, 9.0));
      expect(j.decorrido, Duration.zero);
      expect(j.total, const Duration(seconds: 2));
    });

    test('a posição fora do intervalo (cache ainda não atualizado): a janela inclui-a', () {
      final j = janelaDe({
        'time-pos': '8',
        'seekable': 'no',
        'demuxer-cache-state': _cache(intervalos: [(10, 20)], fim: 20),
      })!;
      expect(j.inicio, 8);
      expect(j.fracao(j.posicao), 0);
    });

    test('sem posição (a abrir) ou cache ilegível: null / só o que se sabe', () {
      expect(janelaDe(const {}), isNull);
      expect(janelaDe(const {'time-pos': '', 'duration': '30', 'seekable': 'yes'}), isNull);
      final j = janelaDe(const {'time-pos': '3', 'seekable': 'no', 'demuxer-cache-state': '{isto não é json'})!;
      expect((j.inicio, j.fim, j.direto), (3.0, 3.0, true));
      expect(j.fracao(3), 0, reason: 'janela vazia: nada a dividir por zero');
      expect(j.fracaoBuffer, 0);
    });

    test('seekable de verdade mas sem duração: janela do cache, seek de ficheiro (não é direto)', () {
      final j = janelaDe({
        'time-pos': '20',
        'seekable': 'yes',
        'partially-seekable': 'no',
        'demuxer-cache-state': _cache(intervalos: [(0, 40)], fim: 40),
      })!;
      expect(j.direto, isFalse, reason: 'o mesmo que o ContinuarDireto: um ficheiro com fim');
      expect((j.inicio, j.fim), (0.0, 40.0));
    });

    test('seekable=no com uma duração qualquer (direto TS no corte): direto', () {
      final j = janelaDe({'time-pos': '20', 'duration': '30', 'seekable': 'no'})!;
      expect(j.direto, isTrue);
    });

    test('filme sem cache-state: sem buffer à frente', () {
      final j = janelaDe(const {'time-pos': '10', 'duration': '100', 'seekable': 'yes'})!;
      expect(j.direto, isFalse);
      expect(j.bufferAte, isNull);
      expect(j.fracaoBuffer, closeTo(.1, 1e-9));
    });
  });

  group('alvos de seek (sempre dentro da janela)', () {
    final direto = janelaDe({
      'time-pos': '100',
      'seekable': 'yes',
      'partially-seekable': 'yes',
      'demuxer-cache-state': _cache(intervalos: [(60, 103)], fim: 103),
    })!;

    test('deslocado ±10 s a partir da posição (ou de um alvo ainda a caminho)', () {
      expect(direto.deslocado(const Duration(seconds: -10)), 90);
      expect(direto.deslocado(const Duration(seconds: 10)), 103, reason: 'nem para lá do mais recente');
    });

    test('direto: o início dos seeks fica 3 s para dentro do cache (o mais antigo vai saindo, e o seek vai '
        'à imagem-chave antes)', () {
      expect(JanelaProgresso.margemInicio, const Duration(seconds: 3));
      expect(direto.deslocado(const Duration(seconds: -10), de: 65), 63);
      expect(direto.alvoPorFracao(0), 63);
      expect(direto.alvoPorFracao(-1), 63);
      // a barra desenha-se na mesma desde o início do cache
      expect(direto.inicio, 60);
      expect(direto.fracao(60), 0);
    });

    test('direto: já dentro da margem, recuar não empurra para a frente', () {
      final perto = JanelaProgresso(inicio: 60, fim: 103, posicao: 61, direto: true);
      expect(perto.deslocado(const Duration(seconds: -10)), 61);
      final curta = JanelaProgresso(inicio: 7, fim: 9, posicao: 7, direto: true);
      expect(curta.alvoPorFracao(0), 7);
      expect(curta.deslocado(const Duration(seconds: -10)), 7);
    });

    test('filme: sem margem (vai ao 0)', () {
      final filme = JanelaProgresso(inicio: 0, fim: 600, posicao: 5, direto: false);
      expect(filme.deslocado(const Duration(seconds: -10)), 0);
      expect(filme.alvoPorFracao(0), 0);
    });

    test('por fração (arrasto/toque), limitada a [0, 1]', () {
      expect(direto.alvoPorFracao(.5), 81.5);
      expect(direto.alvoPorFracao(1.7), 103);
    });

    test('o tempo à esquerda de um alvo é relativo ao início da janela', () {
      expect(direto.decorridoEm(90), const Duration(seconds: 30));
    });
  });
}
