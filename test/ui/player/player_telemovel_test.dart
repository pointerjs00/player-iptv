import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/ui/player/controlos_player.dart';
import 'package:player_iptv/ui/player/painel_definicoes.dart';

import '../apoio_telemovel.dart';

/// O player num telemóvel ao alto (360×800 e 412×915, letra a 1 e a 1,3, com a Roboto): o nome
/// do canal lê-se (até 2 linhas), os botões não se partem em duas filas e os ajustes rápidos não
/// partem palavras a meio.

const _canal = '|PT| SPORT TV 1 FHD (DIRETO)';

List<ItemDefinicao> _ajustes() => [
      DefinicaoEscolha('Desentrelaçamento', opcoes: const ['Desligado', 'Ligado'], atual: 0, nota: 'só no motor mpv'),
      DefinicaoEscolha('Descodificação',
          opcoes: const ['Direta', 'Compatível', 'Software'], atual: 1, aoMudar: (_) {}, nota: 'Compatível: para imagem preta ou cores erradas'),
      DefinicaoEscolha('Formato de imagem', opcoes: const ['Ajustar', 'Zoom', 'Esticar'], atual: 0, aoMudar: (_) {}),
      DefinicaoEscolha('Qualidade / faixa de vídeo', opcoes: const ['Automática'], atual: 0, nota: 'Este canal só tem uma'),
      DefinicaoEscolha('Faixa de áudio', opcoes: const ['Automática'], atual: 0, nota: 'Este canal só tem uma'),
      DefinicaoEscolha('Legendas', opcoes: const ['Desligadas'], atual: 0, nota: 'Este canal não tem legendas'),
      DefinicaoPassos('Volume', valor: '100 %', menos: () {}, mais: () {}),
      DefinicaoAcao('Informação do stream', valor: 'Mostrar', aoCarregar: () {}),
    ];

/// O texto não parte nenhuma palavra a meio (cada mudança de linha é num espaço).
void _semPartirPalavras(WidgetTester t, Finder texto) {
  final p = paragrafo(t, texto);
  final s = p.text.toPlainText();
  double? topo(int i) {
    final caixas = p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    return caixas.isEmpty ? null : caixas.first.top;
  }

  for (var i = 1; i < s.length; i++) {
    final antes = topo(i - 1), agora = topo(i);
    if (antes == null || agora == null || (agora - antes).abs() < 1) continue;
    // muda de linha entre i-1 e i: só num espaço (ou depois de uma barra)
    expect(s[i - 1] == ' ' || s[i] == ' ' || s[i - 1] == '/', isTrue,
        reason: '«$s» parte-se a meio de uma palavra (em ${s.substring(0, i)}|)');
  }
}

void main() {
  setUpAll(carregarRoboto);

  /// Android (não TV) e, no fim do corpo, o repor (antes das verificações do teste).
  void noAndroid(String nome, Future<void> Function(WidgetTester t, Size ecra) corpo) =>
      noTelemovel(nome, (t, ecra) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await corpo(t, ecra);
        } finally {
          // os relógios da barra param com o player
          await t.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> montar(WidgetTester t, {bool podeAlternar = true, Duration atraso = Duration.zero}) async {
    await t.pumpWidget(appTelemovel(Scaffold(
      backgroundColor: Colors.black,
      body: ControlosPlayer(
        estado: EstadoControlos(
          numero: 1,
          canal: _canal,
          subtitulo: subtituloCanal(lista: '001ALFA 070927', grupo: '|PT| DESPORTO'),
          podeAlternar: podeAlternar,
        ),
        atraso: () => atraso,
        aoAgir: (_) {},
        aoMudarVelocidade: (_) {},
        esconderApos: const Duration(hours: 1),
        lerInfoStream: () async => const {},
        definicoes: _ajustes,
        child: const SizedBox.expand(),
      ),
    )));
    await t.pump();
    await t.tapAt(const Offset(150, 200)); // mostra a barra
    await t.pump(const Duration(milliseconds: 600));
  }

  noAndroid('ao alto: o nome do canal lê-se inteiro (2 linhas) e a pílula não lhe come a largura', (t, ecra) async {
    await montar(t);
    // o da barra (o primeiro é o do zapping, escondido; também vai até 2 linhas)
    for (final n in find.text(_canal).evaluate()) {
      expect((n.widget as Text).maxLines, 2);
    }
    final nome = find.text(_canal).last;
    inteiro(t, nome);
    // a pílula «Em direto» fica por baixo do nome (não ao lado)
    expect(t.getRect(find.text('Em direto')).top, greaterThanOrEqualTo(t.getRect(nome).bottom - .5));
    noEcra(t, find.text('Em direto'), ecra);
  });

  noAndroid('ao alto: ⚙ e a velocidade na linha do ←; ⏮ ⏪ ⏯ ⏩ ⏭ numa só linha', (t, ecra) async {
    await montar(t);
    final voltar = t.getCenter(find.byTooltip('Voltar')).dy;
    for (final dica in ['Definições', 'Velocidade', 'Canal visto antes']) {
      expect(t.getCenter(find.byTooltip(dica)).dy, moreOrLessEquals(voltar, epsilon: 1), reason: dica);
      noEcra(t, find.byTooltip(dica), ecra, motivo: dica);
      alvo48(t, find.byTooltip(dica), motivo: dica);
    }
    final play = t.getCenter(find.byTooltip('Pausa')).dy;
    for (final dica in ['Canal anterior', 'Recuar 10 s', 'Avançar 10 s', 'Canal seguinte']) {
      expect(t.getCenter(find.byTooltip(dica)).dy, moreOrLessEquals(play, epsilon: 1), reason: dica);
      noEcra(t, find.byTooltip(dica), ecra, motivo: dica);
      alvo48(t, find.byTooltip(dica), motivo: dica);
    }
  });

  noAndroid('atrás do direto: «Voltar ao direto» à vista, sem transbordar', (t, ecra) async {
    await montar(t, atraso: const Duration(seconds: 40));
    noEcra(t, find.text('Voltar ao direto'), ecra);
    semReticencias(t, find.text('Voltar ao direto'));
  });

  noAndroid('ajustes rápidos: os rótulos não se partem a meio da palavra', (t, ecra) async {
    await montar(t);
    await t.tap(find.byTooltip('Definições'));
    await t.pump(const Duration(milliseconds: 600));
    var vistos = 0;
    for (final i in _ajustes()) {
      final f = find.text(i.titulo);
      if (f.evaluate().isEmpty) continue; // fora da vista (a lista desliza)
      vistos++;
      _semPartirPalavras(t, f);
    }
    expect(vistos, greaterThanOrEqualTo(4));
    // o valor também cabe (sem reticências)
    semReticencias(t, find.text('Compatível'));
  });
}
