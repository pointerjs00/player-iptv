import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/player_canais.dart';

void main() {
  test('o seek do media_kit ao ligar a superfície num direto não é falha do canal', () {
    // o media_kit faz seek(posição) quando a superfície Android chega; num direto o mpv
    // queixa-se mas o canal continua a tocar
    expect(erroFatalPlayer("Cannot seek in this stream. You can force it with '--force-seekable=yes'."), isFalse);
    expect(erroFatalPlayer("You can force it with '--force-seekable=yes'."), isFalse);
  });

  test('os outros erros continuam a mostrar o cartão de erro', () {
    expect(erroFatalPlayer('Failed to open http://h/1.ts'), isTrue);
    expect(erroFatalPlayer('Failed to recognize file format.'), isTrue);
  });

  test('um pacote estragado no corte da ligação não é falha do canal (o mpv continua)', () {
    // visto no emulador: quando o servidor corta, o último pacote chega a meio e o mpv diz
    // "Error decoding audio." mesmo antes do fim do buffer; o cartão aparecia em vez de continuar
    expect(erroFatalPlayer('Error decoding audio.'), isFalse);
    expect(erroFatalPlayer('Error decoding video.'), isFalse);
  });
}
