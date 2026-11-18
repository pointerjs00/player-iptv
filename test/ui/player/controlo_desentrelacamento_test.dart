import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/compativel_sessao.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';
import 'package:player_iptv/ui/player/controlo_desentrelacamento.dart';
import 'package:player_iptv/ui/player/desentrelacamento.dart';

/// Um mpv de mentira: regista o que se põe e devolve o código que o mpv daria.
class _Mpv implements MotorMpv {
  _Mpv({this.recusaVf = false, this.semResposta = false});
  final bool recusaVf;
  final bool semResposta;
  final chamadas = <String>[];

  @override
  Future<int?> setProperty(String p, String v) async {
    if (semResposta) return null;
    chamadas.add('$p=$v');
    // o libmpv mínimo do media_kit (e um filtro que não existe): -9 (visto com o 0.36 e o 0.42)
    if (p == 'vf' && v.isNotEmpty && recusaVf) return -9;
    return 0;
  }

  @override
  Future<String> getProperty(String p) async => '';
  @override
  Future<void> setRate(double r) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> command(List<String> c) async {}
}

/// O mpv recusa o deinterlace=yes (o d3d11vpp não pode ser criado).
class _MpvRecusaDeinterlace extends _Mpv {
  @override
  Future<int?> setProperty(String p, String v) async {
    await super.setProperty(p, v);
    return p == 'deinterlace' && v == 'yes' ? -9 : 0;
  }
}

const _versao = 'mpv v0.42.0-38-gbcde6b93c';
const _bwdif = 'bwdif=mode=send_field:deint=interlaced';

/// Uma leitura do mpv a tocar um 1080i25 (Windows, software): o que `propriedadesEntrelacamento` lê.
Map<String, String> _leitura({
  String versao = _versao,
  String interlaced = 'yes',
  String altura = '1080',
  String fps = '25.000000',
  String vfFps = '25.000000',
  String hwdec = 'no',
  String vf = '',
  String coreIdle = 'no',
  String eof = 'no',
  String seekable = 'no',
  String idet = '',
  String parcial = 'no',
}) =>
    {
      'mpv-version': versao,
      'video-frame-info/interlaced': interlaced,
      'height': altura,
      'container-fps': fps,
      'estimated-vf-fps': vfFps,
      'hwdec-current': hwdec,
      'vf': vf,
      'core-idle': coreIdle,
      'eof-reached': eof,
      'seekable': seekable,
      'partially-seekable': parcial,
      'vf-metadata/$rotuloIdet': idet,
    };

/// Tudo vazio: o que o MotorForaDaUi devolve num pedido sem resposta (limite de 10 s ou fechado).
Map<String, String> _vazia() => {for (final k in _leitura().keys) k: ''};

String _idet({required int tff, required int prog}) =>
    '{"lavfi.idet.multiple.current_frame":"${tff > prog ? 'tff' : 'progressive'}",'
    '"lavfi.idet.multiple.tff":"$tff.00","lavfi.idet.multiple.bff":"0.00",'
    '"lavfi.idet.multiple.progressive":"$prog.00","lavfi.idet.multiple.undetermined":"0.00"}';

void main() {
  late FiltrosNaSessao sessao;
  late CompativelNaSessao compativel;
  setUp(() {
    sessao = FiltrosNaSessao();
    compativel = CompativelNaSessao();
  });

  ControloDesentrelacamento windows() =>
      ControloDesentrelacamento(PlataformaVideo.windows, sessao: sessao, compativel: compativel);
  ControloDesentrelacamento android({bool armv7 = false}) =>
      ControloDesentrelacamento(PlataformaVideo.android, sessao: sessao, compativel: compativel, armv7: armv7);

  Future<void> aplicar(ControloDesentrelacamento c, MotorMpv mpv, {bool direto = false, bool valido = true}) =>
      c.aplicar(mpv,
          ligado: true,
          shaderFlutter: true,
          direto: direto,
          caminhoShader: Future.value('shader.glsl'),
          valido: () => valido);

  /// Lê, aplica e devolve o pedido de reabrir.
  Future<bool> passo(ControloDesentrelacamento c, MotorMpv mpv, Map<String, String> m,
      {bool direto = false, String chave = 'lista|1'}) async {
    final reabrir = c.ler(m, ligado: true, direto: direto, chave: chave);
    if (!reabrir) await aplicar(c, mpv, direto: direto);
    return reabrir;
  }

  group('Windows: o filtro tem de funcionar de facto, senão volta o shader', () {
    test('vf recusado pelo mpv (libmpv sem o filtro): volta o shader, e nesta sessão não se tenta mais', () async {
      final mpv = _Mpv(recusaVf: true);
      final c = windows();
      await passo(c, mpv, _leitura());
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv.chamadas, contains('vf=$_bwdif'));
      expect(mpv.chamadas.last, 'glsl-shaders=shader.glsl');
      expect(sessao.disponivel, isFalse, reason: 'recusado: o filtro não existe neste libmpv');
      // canal seguinte: logo o shader, sem tentar o vf outra vez
      final outro = windows();
      final mpv2 = _Mpv(recusaVf: true);
      await passo(outro, mpv2, _leitura());
      expect(outro.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv2.chamadas.where((s) => s.startsWith('vf=') && s != 'vf='), isEmpty);
    });

    test('leitura vazia (pedido sem resposta) com o filtro posto: o filtro fica (nada muda)', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
      final antes = mpv.chamadas.length;
      for (var i = 0; i < 6; i++) {
        await passo(c, mpv, _vazia());
      }
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
      expect(c.entrelacada, isTrue);
      expect(sessao.disponivel, isTrue, reason: 'a versão lida uma vez fica para a sessão');
      expect(mpv.chamadas.length, antes, reason: 'nenhum vf tirado nem posto');
    });

    test('leitura no fim do buffer (corte: eof, sem altura) ou em pausa: não conta como falha', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      for (var i = 0; i < 6; i++) {
        await passo(c, mpv, _leitura(vf: _bwdif, altura: '', eof: 'yes', vfFps: ''));
        await passo(c, mpv, _leitura(vf: _bwdif, coreIdle: 'yes'));
      }
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
    });

    test('medido a dobrar as imagens (50 de 25): confirmado e fica', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      await passo(c, mpv, _leitura(vf: _bwdif, interlaced: 'no', vfFps: '50.000000'));
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
      expect(c.confirmado, isTrue);
      expect(sessao.confirmado, isTrue);
      expect(c.verificarCedo, isFalse);
    });

    test('posto mas sem efeito (25 imagens/s) várias leituras seguidas: este canal volta ao shader', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      for (var i = 0; i < ControloDesentrelacamento.leiturasSemEfeito; i++) {
        expect(c.meio, MeioDesentrelacamento.filtroMpv);
        await passo(c, mpv, _leitura(vf: _bwdif, interlaced: 'no'));
      }
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(sessao.disponivel, isTrue, reason: 'falhou neste canal, não no libmpv');
      // outro canal: tenta-se de novo
      c.abrir(continuar: false, playerNovo: false);
      await passo(c, mpv, _leitura());
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
    });

    test('o mpv tirou o filtro (vf vazio) com a imagem a correr: volta o shader', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      await passo(c, mpv, _leitura(vf: ''));
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
    });

    test('já confirmado e passa a 25 imagens/s: o canal ficou progressivo, o filtro sai (sem riscar)', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      await passo(c, mpv, _leitura(vf: _bwdif, interlaced: 'no', vfFps: '50'));
      await passo(c, mpv, _leitura(vf: _bwdif, interlaced: 'no', vfFps: '25'));
      expect(c.entrelacada, isFalse);
      expect(c.meio, MeioDesentrelacamento.nenhum);
      expect(mpv.chamadas.last, 'glsl-shaders=');
    });

    test('sem a versão (ainda não se leu nada): o filtro está por saber, não "indisponível"', () {
      final c = windows();
      expect(c.filtrosPorSaber, isTrue);
      c.ler(_leitura(), ligado: true, direto: false, chave: 'k');
      expect(c.filtrosPorSaber, isFalse);
      expect(c.filtros, isTrue);
    });

    test('libmpv 0.36 (o mínimo): sem filtros, o shader, e nunca se põe o vf', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura(versao: 'mpv v0.36.0-403-g652a1dd907'));
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv.chamadas.where((s) => s.startsWith('vf=') && s != 'vf='), isEmpty);
    });

    test('d3d11vpp sem efeito (25 imagens/s) 4 leituras seguidas: volta o shader do mpv (sai do "a medir")', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura(hwdec: 'd3d11va'));
      expect(c.meio, MeioDesentrelacamento.d3d11vpp);
      for (var i = 0; i < ControloDesentrelacamento.leiturasSemEfeito; i++) {
        await passo(c, mpv, _leitura(hwdec: 'd3d11va', interlaced: 'no'));
      }
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv.chamadas.last, 'glsl-shaders=shader.glsl');
      expect(mpv.chamadas, contains('deinterlace=no'));
      expect(c.verificarCedo, isFalse);
      // outro canal: o d3d11vpp tenta-se de novo
      c.abrir(continuar: false, playerNovo: false);
      await passo(c, mpv, _leitura(hwdec: 'd3d11va'));
      expect(c.meio, MeioDesentrelacamento.d3d11vpp);
    });

    test('d3d11vpp recusado pelo mpv (deinterlace=yes < 0): fica o shader, não o d3d11vpp outra vez', () async {
      final mpv = _MpvRecusaDeinterlace();
      final c = windows();
      await passo(c, mpv, _leitura(hwdec: 'd3d11va'));
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv.chamadas.where((x) => x == 'deinterlace=yes').length, 1, reason: 'não se volta a pedir');
      expect(mpv.chamadas.last, 'glsl-shaders=shader.glsl');
      await passo(c, mpv, _leitura(hwdec: 'd3d11va'));
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      expect(mpv.chamadas.where((x) => x == 'deinterlace=yes').length, 1);
    });

    test('pedido sem resposta ao pôr o vf (null): não é recusa; tenta-se na próxima', () async {
      final c = windows();
      await passo(c, _Mpv(semResposta: true), _leitura());
      expect(sessao.disponivel, isTrue);
      expect(c.meio, MeioDesentrelacamento.nenhum, reason: 'nada ficou posto');
      await passo(c, _Mpv(), _leitura());
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
    });
  });

  group('reabrir o mesmo canal num corte do servidor', () {
    test('continuar: fica tudo (entrelaçado, filtro, confirmação); o mpv não perde o vf', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      await passo(c, mpv, _leitura(vf: _bwdif, interlaced: 'no', vfFps: '50'));
      final r = c.abrir(continuar: true, playerNovo: false);
      expect(r.manter, isTrue);
      expect(r.limpar, isFalse);
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
      expect(c.entrelacada, isTrue);
      expect(c.confirmado, isTrue);
      expect(c.verificarCedo, isFalse);
    });

    test('continuar com o d3d11vpp: fica (o aplicarAoAbrir não põe deinterlace=no)', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura(hwdec: 'd3d11va'));
      expect(c.meio, MeioDesentrelacamento.d3d11vpp);
      expect(c.abrir(continuar: true, playerNovo: false).manter, isTrue);
      expect(c.meio, MeioDesentrelacamento.d3d11vpp);
    });

    test('mudar de canal: limpa o filtro do anterior e decide de novo', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      final r = c.abrir(continuar: false, playerNovo: false);
      expect(r.manter, isFalse);
      expect(r.limpar, isTrue);
      expect(c.meio, MeioDesentrelacamento.nenhum);
      expect(c.entrelacada, isNull);
    });

    test('continuar num player novo (o mpv antigo deixou de responder): o mpv novo não tem o vf', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      final r = c.abrir(continuar: true, playerNovo: true);
      expect(r.manter, isFalse);
      expect(c.meio, MeioDesentrelacamento.nenhum, reason: 'o vf volta a pôr-se no mpv novo');
    });

    test('uma falha do filtro fica para o canal (mesmo depois de um corte) mas não para o seguinte', () async {
      final mpv = _Mpv();
      final c = windows();
      await passo(c, mpv, _leitura());
      await passo(c, mpv, _leitura(vf: ''));
      expect(c.meio, MeioDesentrelacamento.shaderMpv);
      c.abrir(continuar: true, playerNovo: false);
      await passo(c, mpv, _leitura());
      expect(c.meio, MeioDesentrelacamento.shaderMpv, reason: 'o mesmo canal: não se tenta outra vez');
      c.abrir(continuar: false, playerNovo: false);
      await passo(c, mpv, _leitura());
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
    });
  });

  test('um pedido na fila de um canal que já mudou não toca no mpv (nem no meio)', () async {
    final mpv = _Mpv();
    final c = windows();
    c.ler(_leitura(), ligado: true, direto: false, chave: 'k');
    await aplicar(c, mpv, valido: false);
    expect(mpv.chamadas, isEmpty);
    expect(c.meio, MeioDesentrelacamento.nenhum);
  });

  group('Android', () {
    Map<String, String> direto(
            {String altura = '1080', String fps = '25.000000', String seekable = 'no', String parcial = 'no'}) =>
        _leitura(hwdec: 'mediacodec', interlaced: '', altura: altura, fps: fps, seekable: seekable, parcial: parcial);

    test('direto: só reabre em Compatível um direto (não um filme) com 1080/576/480 a 25 ou 30 imagens/s', () {
      bool reabre(Map<String, String> m, {String chave = 'k'}) =>
          android().ler(m, ligado: true, direto: true, chave: chave);
      expect(reabre(direto()), isTrue);
      expect(reabre(direto(altura: '576'), chave: 'k2'), isTrue);
      expect(reabre(direto(fps: '29.970030'), chave: 'k3'), isTrue);
      expect(reabre(direto(fps: '23.976024'), chave: 'k4'), isFalse, reason: 'filme a 24 imagens/s: progressivo');
      expect(reabre(direto(fps: '24.000000'), chave: 'k5'), isFalse);
      expect(reabre(direto(seekable: 'yes'), chave: 'k6'), isFalse, reason: 'um filme (VOD), não um direto');
      expect(reabre(direto(seekable: 'yes', parcial: 'yes'), chave: 'k9'), isTrue,
          reason: 'um direto com o cache ligado diz seekable=yes e partially-seekable=yes');
      expect(reabre(direto(altura: '720', fps: '50'), chave: 'k7'), isFalse);
      expect(reabre(direto(fps: '50'), chave: 'k8'), isFalse, reason: '1080p50');
    });

    test('direto: uma vez por canal', () {
      expect(android().ler(direto(), ligado: true, direto: true, chave: 'k'), isTrue);
      expect(android().ler(direto(), ligado: true, direto: true, chave: 'k'), isFalse);
    });

    test('armv7 (Fire TV): nunca o filtro (o bwdif do ffmpeg não tem NEON de 32 bits): fica o shader', () async {
      final c = android(armv7: true);
      expect(c.ler(direto(), ligado: true, direto: true, chave: 'k'), isFalse);
      expect(c.filtros, isFalse);
      final mpv = _Mpv();
      await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: ''));
      expect(c.meio, MeioDesentrelacamento.shaderFlutter);
      expect(mpv.chamadas, isEmpty);
    });

    test('Compatível (mediacodec-copy, sem marcas): o idet marca as imagens e o bwdif só mexe nas entrelaçadas',
        () async {
      final mpv = _Mpv();
      final c = android();
      await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: ''));
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
      expect(mpv.chamadas.last, 'vf=@$rotuloIdet:idet,$_bwdif');
    });

    test('Compatível: o idet diz progressivo e o filtro fica a 25 (o esperado): não é falha', () async {
      final mpv = _Mpv();
      final c = android();
      final vf = '@$rotuloIdet:idet,$_bwdif';
      await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: ''));
      for (var i = 0; i < ControloDesentrelacamento.leiturasSemEfeito + 2; i++) {
        await passo(c, mpv,
            _leitura(hwdec: 'mediacodec-copy', interlaced: '', vf: vf, idet: _idet(tff: 0, prog: 30 * (i + 1))));
      }
      expect(c.meio, MeioDesentrelacamento.filtroMpv);
    });

    test('Compatível: o idet diz entrelaçado mas sai a 25: o filtro não funciona, volta o shader', () async {
      final mpv = _Mpv();
      final c = android();
      final vf = '@$rotuloIdet:idet,$_bwdif';
      await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: ''));
      for (var i = 0; i < ControloDesentrelacamento.leiturasSemEfeito; i++) {
        await passo(c, mpv,
            _leitura(hwdec: 'mediacodec-copy', interlaced: '', vf: vf, idet: _idet(tff: 30 * (i + 1), prog: 0)));
      }
      expect(c.meio, MeioDesentrelacamento.shaderFlutter);
    });

    test('reaberto para o filtro e o idet diz que é progressivo: na próxima vez o canal fica no direto', () async {
      final mpv = _Mpv();
      final c = android();
      expect(c.ler(direto(), ligado: true, direto: true, chave: 'k'), isTrue);
      expect(compativel.modoPara('k', ModoDescodificacao.direto), ModoDescodificacao.compativel);
      c.abrir(continuar: false, playerNovo: true);
      final vf = '@$rotuloIdet:idet,$_bwdif';
      await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: ''), chave: 'k');
      for (var i = 1; i <= 4; i++) {
        await passo(c, mpv, _leitura(hwdec: 'mediacodec-copy', interlaced: '', vf: vf, idet: _idet(tff: 0, prog: 40 * i)),
            chave: 'k');
      }
      expect(compativel.modoPara('k', ModoDescodificacao.direto), ModoDescodificacao.direto);
      expect(android().ler(direto(), ligado: true, direto: true, chave: 'k'), isFalse,
          reason: 'já se sabe que é progressivo: não reabre outra vez');
    });
  });
}
