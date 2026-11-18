import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:player_iptv/dados/biblioteca.dart';
import 'package:player_iptv/importar/importar.dart';
import 'package:player_iptv/modelo/conta.dart';
import 'package:player_iptv/ui/design/design.dart';
import 'package:player_iptv/ui/tema.dart';

Lista _lista(String? estado) => Lista(
      id: 'a',
      ordem: 1,
      conta: contaDeLinha('http://exemplo.pt:8080/get.php?username=u&password=p&type=m3u')!,
      ultima: estado == null ? null : UltimaVerificacao(estado: estado, data: DateTime(2026, 3, 1)),
    );

Widget _app(Widget w) => MaterialApp(theme: temaApp(), home: Scaffold(body: Center(child: w)));

void main() {
  test('estadoDe mapeia cada valor de ultima.estado', () {
    expect(estadoDe(_lista('funciona')), EstadoLista.funciona);
    expect(estadoDe(_lista('inconclusivo')), EstadoLista.inconclusiva);
    expect(estadoDe(_lista('nao_funciona')), EstadoLista.naoFunciona);
    expect(estadoDe(_lista(null)), EstadoLista.porVerificar);
  });

  test('rótulos, cores e fundos', () {
    expect(EstadoLista.funciona.rotulo, 'Funciona');
    expect(EstadoLista.inconclusiva.rotulo, 'Inconclusiva');
    expect(EstadoLista.naoFunciona.rotulo, 'Não funciona');
    expect(EstadoLista.porVerificar.rotulo, 'Por verificar');
    expect(EstadoLista.funciona.cor, Tokens.ok);
    expect(EstadoLista.funciona.fundo, Tokens.fundoOk);
    expect(EstadoLista.inconclusiva.cor, Tokens.aviso);
    expect(EstadoLista.inconclusiva.fundo, Tokens.fundoAviso);
    expect(EstadoLista.naoFunciona.cor, Tokens.mau);
    expect(EstadoLista.naoFunciona.fundo, Tokens.fundoMau);
    expect(EstadoLista.porVerificar.cor, Tokens.neutro);
    expect(EstadoLista.porVerificar.fundo, Tokens.fundoNeutro);
  });

  testWidgets('PilulaEstado mostra o rótulo e o detalhe', (t) async {
    await t.pumpWidget(_app(const PilulaEstado(EstadoLista.naoFunciona, detalhe: 'ontem')));
    expect(find.text('Não funciona · ontem'), findsOneWidget);
    await t.pumpWidget(_app(const PilulaEstado(EstadoLista.funciona)));
    expect(find.text('Funciona'), findsOneWidget);
    final caixa = t.widget<Container>(find.descendant(of: find.byType(PilulaEstado), matching: find.byType(Container)).first);
    expect((caixa.decoration! as BoxDecoration).color, Tokens.fundoOk);
  });
}
