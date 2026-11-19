import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/faixas.dart';
import 'package:player_iptv/ui/player/motor_reproducao.dart';

void main() {
  test('vídeo: "Automática" + a altura de cada faixa; a escolhida', () {
    final faixas = [
      FaixaMotor.auto,
      FaixaMotor.nenhuma,
      const FaixaMotor('1', altura: 1080),
      const FaixaMotor('2', titulo: 'Backup', altura: 720),
      const FaixaMotor('3'),
    ];
    final e = escolhaVideo(faixas, const FaixaMotor('2', titulo: 'Backup'));
    expect(e.opcoes, ['Automática', '1080p', '720p · Backup', 'Faixa 3']);
    expect(e.atual, 2);
    expect(e.faixa(0).id, 'auto');
    expect(e.faixa(1).id, '1');
    expect(escolhaVideo(faixas, FaixaMotor.auto).atual, 0);
  });

  test('áudio: idioma por extenso e codec', () {
    final faixas = [
      FaixaMotor.auto,
      FaixaMotor.nenhuma,
      const FaixaMotor('1', lingua: 'por', codec: 'aac'),
      const FaixaMotor('2', titulo: 'Original', lingua: 'eng', codec: 'ac3'),
      const FaixaMotor('3', lingua: 'xx'),
    ];
    final e = escolhaAudio(faixas, const FaixaMotor('1', lingua: 'por'));
    expect(e.opcoes, ['Automática', 'Português · AAC', 'Inglês · Original · AC3', 'xx']);
    expect(e.atual, 1);
  });

  test('legendas: "Desligadas" + as faixas; a automática conta como desligada', () {
    final faixas = [
      FaixaMotor.auto,
      FaixaMotor.nenhuma,
      const FaixaMotor('1', lingua: 'por'),
    ];
    final e = escolhaLegendas(faixas, FaixaMotor.auto);
    expect(e.opcoes, ['Desligadas', 'Português']);
    expect(e.atual, 0);
    expect(e.faixa(0).id, 'no');
    expect(escolhaLegendas(faixas, const FaixaMotor('1', lingua: 'por')).atual, 1);
    expect(escolhaLegendas([FaixaMotor.auto, FaixaMotor.nenhuma], FaixaMotor.nenhuma).opcoes, ['Desligadas']);
  });
}
