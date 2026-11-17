import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:player_iptv/ui/player/faixas.dart';

void main() {
  test('vídeo: "Automática" + a altura de cada faixa; a escolhida', () {
    final faixas = [
      VideoTrack.auto(),
      VideoTrack.no(),
      const VideoTrack('1', null, null, w: 1920, h: 1080),
      const VideoTrack('2', 'Backup', null, w: 1280, h: 720),
      const VideoTrack('3', null, null),
    ];
    final e = escolhaVideo(faixas, const VideoTrack('2', 'Backup', null));
    expect(e.opcoes, ['Automática', '1080p', '720p · Backup', 'Faixa 3']);
    expect(e.atual, 2);
    expect(e.faixa(0).id, 'auto');
    expect(e.faixa(1).id, '1');
    expect(escolhaVideo(faixas, VideoTrack.auto()).atual, 0);
  });

  test('áudio: idioma por extenso e codec', () {
    final faixas = [
      AudioTrack.auto(),
      AudioTrack.no(),
      const AudioTrack('1', null, 'por', codec: 'aac'),
      const AudioTrack('2', 'Original', 'eng', codec: 'ac3'),
      const AudioTrack('3', null, 'xx'),
    ];
    final e = escolhaAudio(faixas, const AudioTrack('1', null, 'por'));
    expect(e.opcoes, ['Automática', 'Português · AAC', 'Inglês · Original · AC3', 'xx']);
    expect(e.atual, 1);
  });

  test('legendas: "Desligadas" + as faixas; a automática conta como desligada', () {
    final faixas = [
      SubtitleTrack.auto(),
      SubtitleTrack.no(),
      const SubtitleTrack('1', null, 'por'),
    ];
    final e = escolhaLegendas(faixas, SubtitleTrack.auto());
    expect(e.opcoes, ['Desligadas', 'Português']);
    expect(e.atual, 0);
    expect(e.faixa(0).id, 'no');
    expect(escolhaLegendas(faixas, const SubtitleTrack('1', null, 'por')).atual, 1);
    expect(escolhaLegendas([SubtitleTrack.auto(), SubtitleTrack.no()], SubtitleTrack.no()).opcoes, ['Desligadas']);
  });
}
