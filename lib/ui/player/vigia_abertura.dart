import 'dart:async';

/// Decide quando um canal abriu de facto, para o player nunca ficar preto e mudo.
///
/// O media_kit diz `playing = true` logo dentro do `open`, antes de chegar qualquer dado, por
/// isso isso não conta. Conta haver imagem (largura > 0) e o stream andar: o buffering acabou
/// ou a posição avançou. Sem isso ao fim de `limite`, `aoFalhar` (o player mostra o erro com
/// "Tentar de novo").
class VigiaAbertura {
  VigiaAbertura({required this.aoAbrir, required this.aoFalhar, this.limite = const Duration(seconds: 20)});

  final void Function() aoAbrir;
  final void Function(String motivo) aoFalhar;
  final Duration limite;

  Timer? _prazo;
  bool _aVigiar = false;
  bool _anda = false;
  int _largura = 0;

  /// Um canal novo começou a abrir.
  void comecar() {
    _prazo?.cancel();
    _aVigiar = true;
    _anda = false;
    _prazo = Timer(limite, () {
      if (!_aVigiar) return;
      _aVigiar = false;
      aoFalhar('o canal não começou a tempo (sem imagem em ${_segundos(limite)} s)');
    });
  }

  /// Ignorado de propósito (ver a descrição da classe).
  void tocando(bool a) {}

  void buffering(bool b) {
    if (!b) _anda = true;
    _verificar();
  }

  void largura(int? w) {
    _largura = w ?? 0;
    _verificar();
  }

  void tempo(Duration p) {
    if (p > Duration.zero) _anda = true;
    _verificar();
  }

  void _verificar() {
    if (!_aVigiar || !_anda || _largura <= 0) return;
    _aVigiar = false;
    _prazo?.cancel();
    aoAbrir();
  }

  /// O canal falhou por outra razão ou o player fechou.
  void parar() {
    _aVigiar = false;
    _prazo?.cancel();
  }

  static String _segundos(Duration d) =>
      d.inMilliseconds % 1000 == 0 ? '${d.inSeconds}' : '${d.inMilliseconds / 1000}';
}
