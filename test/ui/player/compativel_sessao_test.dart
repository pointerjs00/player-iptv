import 'package:flutter_test/flutter_test.dart';
import 'package:player_iptv/ui/player/compativel_sessao.dart';
import 'package:player_iptv/ui/player/configuracao_mpv.dart';

void main() {
  test('um canal sem imagem no direto passa a Compatível nesta sessão, só esse', () {
    final s = CompativelNaSessao();
    expect(s.modoPara('lista|1', ModoDescodificacao.direto), ModoDescodificacao.direto);
    expect(s.marcar('lista|1'), isTrue, reason: '1.ª vez: reabrir em Compatível');
    expect(s.modoPara('lista|1', ModoDescodificacao.direto), ModoDescodificacao.compativel);
    expect(s.modoPara('lista|2', ModoDescodificacao.direto), ModoDescodificacao.direto);
  });

  test('nunca em ciclo: a 2.ª vez já não manda reabrir', () {
    final s = CompativelNaSessao();
    s.marcar('c');
    expect(s.marcar('c'), isFalse);
  });

  test('quem já prefere Compatível fica igual', () {
    final s = CompativelNaSessao()..marcar('c');
    expect(s.modoPara('c', ModoDescodificacao.compativel), ModoDescodificacao.compativel);
  });

  test('entrelaçado: reabre uma vez para o filtro; visto progressivo volta ao direto e não reabre mais', () {
    final s = CompativelNaSessao();
    expect(s.marcarParaFiltro('c'), isTrue);
    expect(s.modoPara('c', ModoDescodificacao.direto), ModoDescodificacao.compativel);
    expect(s.marcarParaFiltro('c'), isFalse, reason: 'nunca em ciclo');
    s.progressivo('c');
    expect(s.modoPara('c', ModoDescodificacao.direto), ModoDescodificacao.direto);
    expect(s.marcarParaFiltro('c'), isFalse);
  });

  test('um canal sem imagem no direto fica em Compatível mesmo que seja progressivo', () {
    final s = CompativelNaSessao()..marcar('c');
    s.progressivo('c');
    expect(s.modoPara('c', ModoDescodificacao.direto), ModoDescodificacao.compativel);
  });

  test('"Abrir em modo compatível" (cartão de erro): Compatível no Android, software no Windows; só esse canal', () {
    final s = CompativelNaSessao();
    expect(s.software('c'), isFalse);
    s.pedir('c');
    expect(s.modoPara('c', ModoDescodificacao.direto), ModoDescodificacao.compativel);
    expect(s.software('c'), isTrue);
    expect(s.software('d'), isFalse);
    expect(s.modoPara('d', ModoDescodificacao.direto), ModoDescodificacao.direto);
    expect(s.marcarParaFiltro('c'), isFalse, reason: 'já está em Compatível: não há reabertura para o filtro');
  });
}
