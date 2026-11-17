import 'configuracao_mpv.dart';

/// Canais que, nesta sessão da app, não deram imagem na descodificação direta e passaram a
/// "Compatível". Só em memória: a preferência guardada não muda (outros canais continuam no
/// direto). Um canal só passa uma vez: nunca há ciclos de reabrir.
class CompativelNaSessao {
  static final instancia = CompativelNaSessao();

  final _chaves = <String>{};

  ModoDescodificacao modoPara(String chave, ModoDescodificacao preferido) =>
      preferido == ModoDescodificacao.direto && _chaves.contains(chave) ? ModoDescodificacao.compativel : preferido;

  /// Marca o canal; true se é a primeira vez (reabrir em Compatível), false se já estava.
  bool marcar(String chave) => _chaves.add(chave);
}
