import 'configuracao_mpv.dart';

/// Canais que, nesta sessão da app, passaram da descodificação direta a "Compatível": os que não
/// deram imagem no direto e os entrelaçados (o filtro do mpv só corre fora do direto). Só em
/// memória: a preferência guardada não muda (outros canais continuam no direto). Um canal só passa
/// uma vez por cada motivo: nunca há ciclos de reabrir.
class CompativelNaSessao {
  static final instancia = CompativelNaSessao();

  final _semImagem = <String>{};
  final _filtro = <String>{};
  final _progressivos = <String>{};

  ModoDescodificacao modoPara(String chave, ModoDescodificacao preferido) =>
      preferido == ModoDescodificacao.direto && (_semImagem.contains(chave) || _filtro.contains(chave))
          ? ModoDescodificacao.compativel
          : preferido;

  /// Marca o canal (sem imagem no direto); true se é a primeira vez (reabrir em Compatível).
  bool marcar(String chave) => _semImagem.add(chave) && !_filtro.contains(chave);

  /// Marca o canal para o filtro de desentrelaçamento; true se é a primeira vez e não se sabe já
  /// que é progressivo (reabrir em Compatível).
  bool marcarParaFiltro(String chave) =>
      !_progressivos.contains(chave) && !_semImagem.contains(chave) && _filtro.add(chave);

  /// O canal, visto em Compatível, é progressivo (o idet do mpv): da próxima vez abre no direto e
  /// não volta a ser reaberto para o filtro nesta sessão.
  void progressivo(String chave) {
    _progressivos.add(chave);
    _filtro.remove(chave);
  }

  bool eProgressivo(String chave) => _progressivos.contains(chave);

  /// Reaberto para o filtro (e ainda não visto progressivo).
  bool paraFiltro(String chave) => _filtro.contains(chave);
}
