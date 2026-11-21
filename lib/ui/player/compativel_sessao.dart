import 'configuracao_mpv.dart';

/// Canais que, nesta sessão da app, passaram da descodificação direta a "Compatível": os que não
/// deram imagem no direto e os entrelaçados (o filtro do mpv só corre fora do direto). Só em
/// memória: a preferência guardada não muda (outros canais continuam no direto). Um canal só passa
/// uma vez por cada motivo: nunca há ciclos de reabrir.
class CompativelNaSessao {
  CompativelNaSessao({DateTime Function()? relogio}) : _relogio = relogio ?? DateTime.now;

  static final instancia = CompativelNaSessao();

  /// Quanto tempo um canal que perdeu imagens em Compatível fica sem voltar a ser reaberto para o filtro.
  static const duracaoLento = Duration(minutes: 10);

  final DateTime Function() _relogio;

  final _semImagem = <String>{};
  final _filtro = <String>{};
  final _progressivos = <String, String?>{};
  final _lentos = <String, DateTime>{};

  ModoDescodificacao modoPara(String chave, ModoDescodificacao preferido) =>
      preferido == ModoDescodificacao.direto && (_semImagem.contains(chave) || _filtro.contains(chave))
          ? ModoDescodificacao.compativel
          : preferido;

  final _pedidos = <String>{};

  /// O utilizador pediu "Abrir em modo compatível" (cartão de erro): no Android o canal fica em
  /// Compatível nesta sessão (como um canal sem imagem no direto: nunca volta ao direto sozinho);
  /// no Windows, onde não há esse modo, fica com a descodificação por software ([software]).
  void pedir(String chave) {
    _semImagem.add(chave);
    _pedidos.add(chave);
  }

  /// Windows: o canal abre com a descodificação por software (pedido no cartão de erro).
  bool software(String chave) => _pedidos.contains(chave);

  /// Marca o canal (sem imagem no direto); true se é a primeira vez (reabrir em Compatível).
  bool marcar(String chave) => _semImagem.add(chave) && !_filtro.contains(chave);

  /// Marca o canal para o filtro de desentrelaçamento; true se é a primeira vez e não se sabe já
  /// que é progressivo (reabrir em Compatível).
  bool marcarParaFiltro(String chave) =>
      !_progressivos.containsKey(chave) && !eLento(chave) && !_semImagem.contains(chave) && _filtro.add(chave);

  /// O canal, visto em Compatível, é progressivo (o idet do mpv): da próxima vez abre no direto e
  /// não volta a ser reaberto para o filtro nesta sessão.
  /// `assinatura`: a altura e as imagens/s em que foi visto; se o canal mudar de formato deixa de valer.
  void progressivo(String chave, [String? assinatura]) {
    _progressivos[chave] = assinatura;
    _filtro.remove(chave);
  }

  bool eProgressivo(String chave) => _progressivos.containsKey(chave);

  /// A assinatura (altura@fps) com que o canal foi visto progressivo; null se não se guardou.
  String? assinaturaProgressivo(String chave) => _progressivos[chave];

  /// O canal já não vale como progressivo (o mpv viu riscas ou o formato mudou).
  void esquecerProgressivo(String chave) => _progressivos.remove(chave);

  /// Em Compatível com o filtro o aparelho perde imagens (não aguenta a cópia + o bwdif): o canal
  /// volta ao direto (com o shader) e não volta a ser reaberto para o filtro durante [duracaoLento]
  /// (uma má fase da rede ou do aparelho não o condena a sessão inteira).
  void lento(String chave) {
    _lentos[chave] = _relogio();
    _filtro.remove(chave);
  }

  bool eLento(String chave) {
    final desde = _lentos[chave];
    if (desde == null) return false;
    if (_relogio().difference(desde) < duracaoLento) return true;
    _lentos.remove(chave);
    return false;
  }

  /// Reaberto para o filtro (e ainda não visto progressivo).
  bool paraFiltro(String chave) => _filtro.contains(chave);
}
