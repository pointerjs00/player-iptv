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
  ControloDesentrelacamento(this.plataforma, {FiltrosNaSessao? sessao, CompativelNaSessao? compativel, bool? armv7})
      : sessao = sessao ?? FiltrosNaSessao.instancia,
        compativel = compativel ?? CompativelNaSessao.instancia,
        armv7 = armv7 ?? (plataforma == PlataformaVideo.android && Abi.current() == Abi.androidArm);

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
  bool _falhouNoCanal = false;
  bool _confirmado = false;
  int _semEfeito = 0;
  int _leiturasIdet = 0;
  Future<void> _fila = Future.value();

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
      _confirmado = false;
      _semEfeito = 0;
      // o mesmo canal num mpv novo: a imagem e uma falha do filtro continuam a valer
      if (!continuar) _esquecerCanal();
      return (manter: false, limpar: false);
    }
    if (continuar) return (manter: true, limpar: false);
    final limpar = _meio == MeioDesentrelacamento.filtroMpv;
    if (limpar || _meio == MeioDesentrelacamento.d3d11vpp) _meio = MeioDesentrelacamento.nenhum;
    _confirmado = false;
    _semEfeito = 0;
    _esquecerCanal();
    return (manter: false, limpar: limpar);
  }

  void _esquecerCanal() {
    _entrelacada = null;
    _falhouNoCanal = false;
    _leiturasIdet = 0;
  }

  /// Lê o que o mpv disse ([propriedadesEntrelacamento]). Uma leitura sem resposta (vazia) não muda
  /// nada. Devolve true quando o canal (Android direto) deve reabrir em Compatível para o filtro: o
  /// [CompativelNaSessao] já ficou marcado.
  bool ler(Map<String, String> m, {required bool ligado, required bool direto, required String chave}) {
    if ((m['mpv-version'] ?? '').trim().isEmpty) return false;
    sessao.versao(m['mpv-version']);
    final hw = (m['hwdec-current'] ?? '').trim();
    if (hw.isNotEmpty) _hwdec = hw;
    final lida = imagemEntrelacada(m);
    if (_meio == MeioDesentrelacamento.filtroMpv || _meio == MeioDesentrelacamento.d3d11vpp) {
      _medir(m, chave);
    } else if (lida != null) {
      _entrelacada = lida;
    }
    if (plataforma == PlataformaVideo.android &&
        ligado &&
        direto &&
        filtros &&
        pareceEntrelacadaNoDireto(m) &&
        compativel.marcarParaFiltro(chave)) {
      return true;
    }
    return false;
  }

  bool get _comIdet => plataforma == PlataformaVideo.android && _hwdec.startsWith('mediacodec');

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

  MeioDesentrelacamento _meioPara({required bool ligado, required bool shaderFlutter, required bool direto}) =>
      meioDesentrelacamento(plataforma,
          ligado: ligado,
          entrelacada: _entrelacada,
          hwdec: _hwdec,
          shaderFlutter: shaderFlutter,
          filtros: filtros,
          direto: plataforma == PlataformaVideo.android && direto);

  /// Põe o meio que serve agora (preferência, imagem, aparelho). Em fila: uma mudança da preferência
  /// a meio de uma verificação não fica trocada. `valido`: o pedido ainda é do canal atual (vê-se já
  /// na vez do pedido; um pedido de um canal anterior não toca no mpv do novo). Devolve true se o
  /// meio mudou. Nunca lança.
  Future<bool> aplicar(MotorMpv mpv,
      {required bool ligado,
      required bool shaderFlutter,
      required bool direto,
      required Future<String?> caminhoShader,
      required bool Function() valido}) {
    final r = _fila.then((_) => _aplicar(mpv,
        ligado: ligado, shaderFlutter: shaderFlutter, direto: direto, caminhoShader: caminhoShader, valido: valido));
    _fila = r.then<void>((_) {}, onError: (_) {});
    return r.catchError((Object e) {
      debugPrint('desentrelaçamento: $e');
      return false;
    });
  }

  Future<bool> _aplicar(MotorMpv mpv,
      {required bool ligado,
      required bool shaderFlutter,
      required bool direto,
      required Future<String?> caminhoShader,
      required bool Function() valido}) async {
    if (!valido()) return false;
    var meio = _meioPara(ligado: ligado, shaderFlutter: shaderFlutter, direto: direto);
    if (meio == _meio) return false;
    final antes = _meio;
    final shader = await caminhoShader;
    if (!valido()) return false;
    // no Android o mpv só leva o filtro (o shader é do Flutter); se o filtro sai, limpa-se o vf
    final noMpv = plataforma != PlataformaVideo.android ||
        meio == MeioDesentrelacamento.filtroMpv ||
        _meio == MeioDesentrelacamento.filtroMpv;
    if (noMpv) {
      // com limite: um setProperty preso não pode deixar a fila parada (as mudanças seguintes)
      final codigo = await aplicarMeioMpv(mpv, meio, caminhoShader: shader, hwdec: _hwdec)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (codigo == null) return false; // sem resposta: tenta-se na próxima verificação
      if (codigo < 0) {
        if (meio == MeioDesentrelacamento.filtroMpv) {
          debugPrint('desentrelaçamento: o mpv recusou o filtro ($codigo); volta o shader');
          sessao.recusou();
        } else {
          _falhar('o mpv recusou o d3d11vpp ($codigo)');
        }
        meio = _meioPara(ligado: ligado, shaderFlutter: shaderFlutter, direto: direto);
        if (!valido()) return false;
        if (plataforma != PlataformaVideo.android || meio != MeioDesentrelacamento.shaderFlutter) {
          await aplicarMeioMpv(mpv, meio, caminhoShader: shader, hwdec: _hwdec)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
        } else {
          await mpv.setProperty('vf', '').timeout(const Duration(seconds: 3), onTimeout: () => null);
        }
      }
    }
    _meio = meio;
    if (meio != antes) {
      _confirmado = false;
      _semEfeito = 0;
    }
    return meio != antes;
  }
}
