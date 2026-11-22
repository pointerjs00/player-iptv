import 'dart:async';
import '../../idioma/idioma.dart';

/// Decide quando um canal abriu de facto (há imagem no ecrã), para o player nunca ficar preto e
/// mudo, e para o indicador "a abrir" ficar até à primeira imagem.
///
/// Não contam: o `playing = true` que o media_kit diz logo no `open`; o `buffering = false` e a
/// posição 0 que o `stop()` de dentro do `open()` manda (visto no emulador); a largura, que o mpv
/// sabe assim que o descodificador arranca, antes de mostrar a primeira imagem. Conta haver
/// imagem (largura > 0) e a posição andar [avanco] desde então, sem pausa para buffer: o vídeo
/// está mesmo a tocar. Sem isso ao fim de `limite`, `aoFalhar` (o player mostra o erro com
/// "Tentar de novo").
class VigiaAbertura {
  VigiaAbertura({required this.aoAbrir, required this.aoFalhar, this.limite = const Duration(seconds: 20),
      this.avanco = const Duration(milliseconds: 300)});

  final void Function() aoAbrir;
  final void Function(String motivo) aoFalhar;
  final Duration limite;

  /// Quanto a posição tem de andar, com imagem, para o canal contar como aberto.
  final Duration avanco;

  Timer? _prazo;
  bool _aVigiar = false;
  // só depois do open() deste canal: até lá os eventos são do canal anterior
  bool _aceitar = false;
  bool _buffering = false;
  int _largura = 0;
  // a posição quando começou a contar (com imagem e sem buffering); null = ainda não
  Duration? _desde;

  /// Um canal novo começou a abrir (o link ainda se está a resolver: o canal anterior pode
  /// continuar a tocar e a mandar eventos, que não contam para este).
  void comecar() {
    _prazo?.cancel();
    _aVigiar = true;
    _aceitar = false;
    _reiniciar();
    _prazo = Timer(limite, () {
      if (!_aVigiar) return;
      _aVigiar = false;
      aoFalhar(tr('o canal não começou a tempo (sem imagem em {0} s)', [_segundos(limite)]));
    });
  }

  /// O player vai abrir este canal (chamado mesmo antes do `open()`): daqui em diante os
  /// eventos são dele.
  void abrindo() {
    _aceitar = true;
    _reiniciar();
  }

  void _reiniciar() {
    _buffering = false;
    _largura = 0;
    _desde = null;
  }

  /// Ignorado de propósito (ver a descrição da classe).
  void tocando(bool a) {}

  void buffering(bool b) {
    if (!_aceitar) return;
    _buffering = b;
    if (b) _desde = null; // parado à espera de dados: a contagem recomeça quando voltar a andar
  }

  void largura(int? w) {
    if (!_aceitar) return;
    _largura = w ?? 0;
    if (_largura <= 0) _desde = null;
  }

  void tempo(Duration p) {
    if (!_aceitar || !_aVigiar || _buffering || _largura <= 0) return;
    final desde = _desde;
    if (desde == null || p < desde) {
      _desde = p;
      return;
    }
    if (p - desde < avanco) return;
    _aVigiar = false;
    _prazo?.cancel();
    aoAbrir();
  }

  /// O motor diz que a primeira imagem deste canal chegou ao ecrã (o ExoPlayer: `onRenderedFirstFrame`):
  /// abre já, sem esperar que a posição ande (que só chega a cada 500 ms).
  void imagem() {
    if (!_aceitar || !_aVigiar) return;
    _aVigiar = false;
    _prazo?.cancel();
    aoAbrir();
  }

  /// O canal falhou por outra razão ou o player fechou.
  void parar() {
    _aVigiar = false;
    _aceitar = false;
    _prazo?.cancel();
  }

  static String _segundos(Duration d) =>
      d.inMilliseconds % 1000 == 0 ? '${d.inSeconds}' : '${d.inMilliseconds / 1000}';
}
