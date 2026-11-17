import 'package:media_kit/media_kit.dart';

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
EscolhaFaixa<VideoTrack> escolhaVideo(List<VideoTrack> todas, VideoTrack atual) => _escolha(
    todas, atual, (t) => t.id, VideoTrack.auto(), 'Automática',
    (t, n) => _juntar([if ((t.h ?? 0) > 0) '${t.h}p', t.title], n));

/// "Automática", "Português · AAC".
EscolhaFaixa<AudioTrack> escolhaAudio(List<AudioTrack> todas, AudioTrack atual) => _escolha(
    todas, atual, (t) => t.id, AudioTrack.auto(), 'Automática',
    (t, n) => _juntar([_idioma(t.language), t.title, t.codec?.toUpperCase()], n));

/// "Desligadas", "Português". A escolha automática do mpv (sem legendas, num direto) conta
/// como desligadas.
EscolhaFaixa<SubtitleTrack> escolhaLegendas(List<SubtitleTrack> todas, SubtitleTrack atual) => _escolha(
    todas, atual, (t) => t.id, SubtitleTrack.no(), 'Desligadas',
    (t, n) => _juntar([_idioma(t.language), t.title], n));
