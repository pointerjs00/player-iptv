import 'dart:async';
import 'dart:ffi' show Abi;

import 'package:flutter/foundation.dart';

import 'compativel_sessao.dart';
import 'configuracao_mpv.dart';
import 'desentrelacamento.dart';

/// O que esta sessão da app (o processo: o mesmo libmpv em todos os players) já sabe dos filtros do
/// ffmpeg no libmpv. Fica de um canal para o outro e nunca volta atrás por uma leitura vazia.
class FiltrosNaSessao {
  static final instancia = FiltrosNaSessao();

  bool? _versaoServe;
  bool _recusado = false;
  bool _confirmado = false;

  /// Uma versão lida com sucesso (as vazias, de um pedido sem resposta, não contam).
  void versao(String? v) {
    if ((v ?? '').trim().isEmpty) return;
    _versaoServe ??= filtrosDoMpv(v);
  }

  /// O mpv recusou o `vf` (o filtro não pode ser criado neste libmpv): não se tenta mais.
  void recusou() => _recusado = true;

  /// O filtro foi medido a dobrar as imagens (funciona neste libmpv).
  void confirmou() => _confirmado = true;

  /// Ainda não se leu a versão do mpv.
  bool get porSaber => _versaoServe == null && !_recusado;
  bool get disponivel => _versaoServe == true && !_recusado;
  bool get confirmado => _confirmado;
}

/// O desentrelaçamento de um player: o que se sabe da imagem do canal, o meio posto no mpv e se o
/// filtro funciona de facto (medido, ver [efeitoFiltro]). Sem mpv nem UI: o `PlayerCanais` lê as
/// propriedades ([propriedadesEntrelacamento]), passa-as a [ler] e chama [aplicar].
class ControloDesentrelacamento {
  ControloDesentrelacamento(this.plataforma,
      {FiltrosNaSessao? sessao, CompativelNaSessao? compativel, bool? armv7, DateTime Function()? relogio})
      : sessao = sessao ?? FiltrosNaSessao.instancia,
        compativel = compativel ?? CompativelNaSessao.instancia,
        armv7 = armv7 ?? (plataforma == PlataformaVideo.android && Abi.current() == Abi.androidArm),
        _relogio = relogio ?? DateTime.now;

  final DateTime Function() _relogio;

  /// Android, reaberto em Compatível para o filtro: a partir de quantas imagens perdidas por segundo
  /// (o `frame-drop-count` mais o `decoder-frame-drop-count` do mpv) o aparelho não aguenta a cópia
  /// das imagens + o bwdif e o canal volta ao direto. 2/s é 4 % das 50 imagens/s do bwdif: já se vê
  /// a imagem a saltar; as poucas do arranque não chegam lá numa janela de [janelaPerdidas].
  static const perdidasPorSegundo = 2.0;
  static const janelaPerdidas = Duration(seconds: 8);

  final PlataformaVideo plataforma;
  final FiltrosNaSessao sessao;
  final CompativelNaSessao compativel;

  /// Android de 32 bits (armv7: Fire TV Stick e afins). O bwdif e o idet do ffmpeg só têm código
  /// otimizado para x86 e aarch64: em C, 1080i a 50 imagens/s mais a cópia do mediacodec-copy não
  /// cabem nesses CPUs. Fica o shader do Flutter (25 imagens/s, na GPU).
  final bool armv7;

  /// Leituras seguidas com o filtro posto sem efeito (ou sem imagem) até se desistir dele no canal.
  static const leiturasSemEfeito = 4;

  bool? _entrelacada;
  String _hwdec = '';
  MeioDesentrelacamento _meio = MeioDesentrelacamento.nenhum;

  /// O filtro posto é o de todas as imagens (`deint=all`, o modo Ligado).
  bool _todas = false;
  bool _falhouNoCanal = false;
  bool _confirmado = false;
  int _semEfeito = 0;
  int _leiturasIdet = 0;
  Future<void> _fila = Future.value();
  ({DateTime quando, int perdidas})? _basePerdidas;
  String? _avisoReabrir;

  /// O que dizer ao utilizador quando [ler] pede para reabrir o canal.
  String? get avisoReabrir => _avisoReabrir;

  /// A imagem é entrelaçada? null: ainda não se sabe.
  bool? get entrelacada => _entrelacada;
  MeioDesentrelacamento get meio => _meio;
  String get hwdec => _hwdec;

  /// O filtro (ou o d3d11vpp) deste canal já foi medido a dobrar as imagens.
  bool get confirmado => _confirmado;

  /// Há filtros para este canal: o libmpv tem-nos, não falharam aqui e o aparelho aguenta-os.
  bool get filtros => sessao.disponivel && !_falhouNoCanal && !(plataforma == PlataformaVideo.android && armv7);

  /// Ainda não se leu o mpv (o painel não pode prometer nem negar as 50 imagens/s).
  bool get filtrosPorSaber => sessao.porSaber && !(plataforma == PlataformaVideo.android && armv7);

  /// Volta a ler daqui a 1 s (e não a cada 10 s): a imagem ainda por saber ou o filtro por medir.
  bool get verificarCedo =>
      _entrelacada == null ||
      ((_meio == MeioDesentrelacamento.filtroMpv || _meio == MeioDesentrelacamento.d3d11vpp) && !_confirmado && !_falhouNoCanal);

  /// Um canal vai abrir. `continuar`: o mesmo canal outra vez (o servidor cortou); `playerNovo`: o
  /// mpv foi recriado (não tem o `vf` do anterior). Devolve `manter`: o mpv fica como está (nem
  /// `deinterlace=no` nem tirar o `vf`: sem um segundo com riscas nem refazer os filtros); `limpar`:
  /// tirar o `vf` do canal anterior.
  ({bool manter, bool limpar}) abrir({required bool continuar, required bool playerNovo}) {
    if (playerNovo) {
      _meio = MeioDesentrelacamento.nenhum;
      _todas = false;
      _confirmado = false;
      _semEfeito = 0;
      // o mesmo canal num mpv novo: a imagem e uma falha do filtro continuam a valer
      if (!continuar) _esquecerCanal();
      return (manter: false, limpar: false);
    }
    if (continuar) return (manter: true, limpar: false);
    final limpar = _meio == MeioDesentrelacamento.filtroMpv;
    if (limpar || _meio == MeioDesentrelacamento.d3d11vpp) _meio = MeioDesentrelacamento.nenhum;
    _todas = false;
    _confirmado = false;
    _semEfeito = 0;
    _esquecerCanal();
    return (manter: false, limpar: limpar);
  }

  void _esquecerCanal() {
    _basePerdidas = null;
    _entrelacada = null;
    _falhouNoCanal = false;
    _leiturasIdet = 0;
  }

  /// Lê o que o mpv disse ([propriedadesEntrelacamento]). Uma leitura sem resposta (vazia) não muda
  /// nada. Devolve true quando o canal (Android direto) deve reabrir em Compatível para o filtro: o
  /// [CompativelNaSessao] já ficou marcado.
  bool ler(Map<String, String> m, {required bool ligado, required bool direto, required String chave}) {
    if ((m['mpv-version'] ?? '').trim().isEmpty) return false;
    _avisoReabrir = null;
    sessao.versao(m['mpv-version']);
    final hw = (m['hwdec-current'] ?? '').trim();
    if (hw.isNotEmpty) _hwdec = hw;
    final lida = imagemEntrelacada(m);
    if (_meio == MeioDesentrelacamento.filtroMpv || _meio == MeioDesentrelacamento.d3d11vpp) {
      _medir(m, chave);
    } else if (lida != null) {
      _entrelacada = lida;
    }
    if (_naoAguenta(m, chave)) {
      compativel.lento(chave);
      _avisoReabrir = 'O aparelho perde imagens com o desentrelaçamento por campo: volta a descodificação Direta';
      debugPrint('desentrelaçamento: o Compatível com o filtro perde imagens; o canal volta ao direto');
      return true;
    }
    if (plataforma == PlataformaVideo.android &&
        ligado &&
        direto &&
        filtros &&
        pareceEntrelacadaNoDireto(m) &&
        compativel.marcarParaFiltro(chave)) {
      _avisoReabrir = 'Modo compatível ativado para desentrelaçar este canal';
      return true;
    }
    return false;
  }

  /// Android, num canal reaberto em Compatível para o filtro, com o filtro a dobrar as imagens: as
  /// imagens perdidas numa janela de pelo menos [janelaPerdidas] passam de [perdidasPorSegundo]? Em
  /// pausa, a carregar ou no fim do buffer a janela recomeça (essas paragens não são do aparelho).
  bool _naoAguenta(Map<String, String> m, String chave) {
    if (plataforma != PlataformaVideo.android ||
        _meio != MeioDesentrelacamento.filtroMpv ||
        !_confirmado ||
        !compativel.paraFiltro(chave)) {
      _basePerdidas = null;
      return false;
    }
    final perdidas = (int.tryParse((m['frame-drop-count'] ?? '').trim()) ?? 0) +
        (int.tryParse((m['decoder-frame-drop-count'] ?? '').trim()) ?? 0);
    final agora = _relogio();
    final parado = (m['core-idle'] ?? '').trim() == 'yes' || (m['eof-reached'] ?? '').trim() == 'yes';
    final base = _basePerdidas;
    if (parado || base == null || perdidas < base.perdidas) {
      _basePerdidas = parado ? null : (quando: agora, perdidas: perdidas);
      return false;
    }
    final passou = agora.difference(base.quando);
    if (passou < janelaPerdidas) return false;
    _basePerdidas = (quando: agora, perdidas: perdidas);
    return (perdidas - base.perdidas) / (passou.inMilliseconds / 1000) > perdidasPorSegundo;
  }

  /// O filtro posto leva o idet (MediaCodec, só as imagens marcadas); o de todas as imagens não.
  bool get _comIdet => plataforma == PlataformaVideo.android && _hwdec.startsWith('mediacodec') && !_todas;

  /// O filtro está no mpv: funciona? (a saída da imagem já não diz se a entrada é entrelaçada: com o
  /// bwdif sai progressiva, por isso mede-se pelas imagens/s).
  void _medir(Map<String, String> m, String chave) {
    final idet = _comIdet ? idetEntrelacado(m['vf-metadata/$rotuloIdet']) : null;
    if (_comIdet && m['vf-metadata/$rotuloIdet']?.trim().isNotEmpty == true) _leiturasIdet++;
    // reaberto para o filtro e o idet vê um progressivo: da próxima vez o canal fica no direto
    if (idet == false && _leiturasIdet >= 3 && compativel.paraFiltro(chave)) compativel.progressivo(chave);
    switch (efeitoFiltro(_meio, m)) {
      case EfeitoFiltro.porSaber:
        return;
      case EfeitoFiltro.removido:
        _falhar('o mpv tirou o filtro');
      case EfeitoFiltro.dobra:
        _confirmado = true;
        _semEfeito = 0;
        sessao.confirmou();
      case EfeitoFiltro.semImagem:
        if (++_semEfeito >= leiturasSemEfeito) _falhar('sem imagem com o filtro');
      case EfeitoFiltro.igual:
        if (_comIdet) {
          // o idet só manda o bwdif mexer nas imagens entrelaçadas: a 25 num progressivo é o esperado
          if (idet == true && ++_semEfeito >= leiturasSemEfeito) _falhar('o idet vê riscas e o filtro não dobra');
        } else if (_confirmado) {
          // dobrava e deixou de dobrar: as imagens deixaram de vir marcadas (o canal ficou progressivo)
          _entrelacada = false;
        } else if (++_semEfeito >= leiturasSemEfeito) {
          _falhar('o filtro não dobra as imagens');
        }
    }
  }

  void _falhar(String motivo) {
    debugPrint('desentrelaçamento: $motivo; volta o shader neste canal');
    _falhouNoCanal = true;
    _semEfeito = 0;
  }

  MeioDesentrelacamento _meioPara(
          {required bool ligado, required bool forcar, required bool shaderFlutter, required bool direto}) =>
      meioDesentrelacamento(plataforma,
          ligado: ligado,
          forcar: forcar,
          entrelacada: _entrelacada,
          hwdec: _hwdec,
          shaderFlutter: shaderFlutter,
          filtros: filtros,
          direto: plataforma == PlataformaVideo.android && direto,
          d3d11vpp: !_falhouNoCanal);

  /// Põe o meio que serve agora (preferência, imagem, aparelho). Em fila: uma mudança da preferência
  /// a meio de uma verificação não fica trocada. `valido`: o pedido ainda é do canal atual (vê-se já
  /// na vez do pedido; um pedido de um canal anterior não toca no mpv do novo). Devolve true se o
  /// meio mudou. Nunca lança. `forcar` (o modo Ligado): também nas imagens progressivas, e o filtro
  /// em todas as imagens (passar de Automático a Ligado com o filtro posto refaz o `vf`).
  Future<bool> aplicar(MotorMpv mpv,
      {required bool ligado,
      bool forcar = false,
      required bool shaderFlutter,
      required bool direto,
      required Future<String?> caminhoShader,
      required bool Function() valido}) {
    final r = _fila.then((_) => _aplicar(mpv,
        ligado: ligado,
        forcar: forcar,
        shaderFlutter: shaderFlutter,
        direto: direto,
        caminhoShader: caminhoShader,
        valido: valido));
    _fila = r.then<void>((_) {}, onError: (_) {});
    return r.catchError((Object e) {
      debugPrint('desentrelaçamento: $e');
      return false;
    });
  }

  Future<bool> _aplicar(MotorMpv mpv,
      {required bool ligado,
      required bool forcar,
      required bool shaderFlutter,
      required bool direto,
      required Future<String?> caminhoShader,
      required bool Function() valido}) async {
    if (!valido()) return false;
    var meio = _meioPara(ligado: ligado, forcar: forcar, shaderFlutter: shaderFlutter, direto: direto);
    // o mesmo meio: só o filtro muda, se passou de Automático a Ligado ou ao contrário
    final soOFiltro = meio == _meio && meio == MeioDesentrelacamento.filtroMpv && forcar != _todas;
    if (meio == _meio && !soOFiltro) return false;
    final antes = _meio;
    final shader = await caminhoShader;
    if (!valido()) return false;
    // no Android o mpv só leva o filtro (o shader é do Flutter); se o filtro sai, limpa-se o vf
    final noMpv = plataforma != PlataformaVideo.android ||
        meio == MeioDesentrelacamento.filtroMpv ||
        _meio == MeioDesentrelacamento.filtroMpv;
    if (noMpv) {
      // com limite: um setProperty preso não pode deixar a fila parada (as mudanças seguintes)
      final codigo = await aplicarMeioMpv(mpv, meio, caminhoShader: shader, hwdec: _hwdec, todas: forcar)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (codigo == null) return false; // sem resposta: tenta-se na próxima verificação
      if (codigo >= 0) _todas = forcar && meio == MeioDesentrelacamento.filtroMpv;
      if (codigo < 0) {
        if (meio == MeioDesentrelacamento.filtroMpv) {
          debugPrint('desentrelaçamento: o mpv recusou o filtro ($codigo); volta o shader');
          sessao.recusou();
        } else {
          _falhar('o mpv recusou o d3d11vpp ($codigo)');
        }
        _todas = false;
        meio = _meioPara(ligado: ligado, forcar: forcar, shaderFlutter: shaderFlutter, direto: direto);
        if (!valido()) return false;
        if (plataforma != PlataformaVideo.android || meio != MeioDesentrelacamento.shaderFlutter) {
          await aplicarMeioMpv(mpv, meio, caminhoShader: shader, hwdec: _hwdec, todas: forcar)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
        } else {
          await mpv.setProperty('vf', '').timeout(const Duration(seconds: 3), onTimeout: () => null);
        }
      }
    }
    _meio = meio;
    if (meio != MeioDesentrelacamento.filtroMpv) _todas = false;
    if (meio != antes || soOFiltro) {
      _confirmado = false;
      _semEfeito = 0;
    }
    return meio != antes;
  }
}
