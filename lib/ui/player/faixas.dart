import 'motor_reproducao.dart';

/// As opções de uma faixa para o painel (rótulos) e a que está escolhida.
class EscolhaFaixa<T> {
  EscolhaFaixa._(this.opcoes, this.atual, this._faixas);
  final List<String> opcoes;
  final int atual;
  final List<T> _faixas;

  /// A faixa da opção `i`.
  T faixa(int i) => _faixas[i];
}

const _idiomas = {
  'por': 'Português', 'pt': 'Português', 'eng': 'Inglês', 'en': 'Inglês', 'spa': 'Espanhol', 'es': 'Espanhol',
  'fra': 'Francês', 'fre': 'Francês', 'fr': 'Francês', 'deu': 'Alemão', 'ger': 'Alemão', 'de': 'Alemão',
  'ita': 'Italiano', 'it': 'Italiano',
};

bool _real(String id) => id != 'auto' && id != 'no';

String _juntar(List<String?> partes, int n) {
  final p = [for (final s in partes) if (s != null && s.trim().isNotEmpty) s.trim()];
  return p.isEmpty ? 'Faixa $n' : p.join(' · ');
}

String? _idioma(String? l) => l == null ? null : (_idiomas[l.toLowerCase()] ?? l);

EscolhaFaixa<T> _escolha<T>(List<T> todas, T atual, String Function(T) id, T primeira, String rotuloPrimeira,
    String Function(T, int) rotulo) {
  final reais = [for (final t in todas) if (_real(id(t))) t];
  final faixas = [primeira, ...reais];
  final i = reais.indexWhere((t) => id(t) == id(atual));
  return EscolhaFaixa._(
    [rotuloPrimeira, for (var n = 0; n < reais.length; n++) rotulo(reais[n], n + 1)],
    i < 0 ? 0 : i + 1,
    faixas,
  );
}

/// "Qualidade / faixa de vídeo": "Automática", "1080p", "720p · Backup".
EscolhaFaixa<FaixaMotor> escolhaVideo(List<FaixaMotor> todas, FaixaMotor atual) => _escolha(
    todas, atual, (t) => t.id, FaixaMotor.auto, 'Automática',
    (t, n) => _juntar([if ((t.altura ?? 0) > 0) '${t.altura}p', t.titulo], n));

/// "Automática", "Português · AAC".
EscolhaFaixa<FaixaMotor> escolhaAudio(List<FaixaMotor> todas, FaixaMotor atual) => _escolha(
    todas, atual, (t) => t.id, FaixaMotor.auto, 'Automática',
    (t, n) => _juntar([_idioma(t.lingua), t.titulo, t.codec?.toUpperCase()], n));

/// "Desligadas", "Português". A escolha automática do mpv (sem legendas, num direto) conta
/// como desligadas.
EscolhaFaixa<FaixaMotor> escolhaLegendas(List<FaixaMotor> todas, FaixaMotor atual) => _escolha(
    todas, atual, (t) => t.id, FaixaMotor.nenhuma, 'Desligadas',
    (t, n) => _juntar([_idioma(t.lingua), t.titulo], n));
