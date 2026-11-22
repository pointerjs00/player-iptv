import 'package:material_ui/material_ui.dart';

import '../design/design.dart';
import '../realce_foco.dart';

/// Abre o ecrã "Como é feita a verificação" (o "i" do Gestor). Voltar fecha-o.
Future<void> abrirComoVerifica(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TelaComoVerifica()),
    );

/// Uma secção do texto: um título e parágrafos (as linhas começadas por "• " são pontos).
typedef _Seccao = (String titulo, List<String> texto);

const List<_Seccao> _seccoes = [
  (
    'O que a verificação quer saber',
    [
      'Se cada lista dá mesmo imagem. Não basta o servidor responder: a verificação abre canais de '
          'teste e confirma que chega vídeo a sério.',
      'No fim, cada lista fica num de três estados:',
      '• Funciona: pelo menos um canal de teste deu imagem.',
      '• Não funciona: há uma prova de que a lista não serve (por exemplo, a conta foi recusada, '
          'expirou, o endereço já não existe ou os canais de teste não existem nela).',
      '• Inconclusiva: não deu imagem, mas também não há prova de que esteja morta (o servidor '
          'estava lento, cortou a ligação, recusou por excesso de ligações…). Nunca se marca uma '
          'lista como "não funciona" só porque demorou.',
    ]
  ),
  (
    '1. O endereço existe?',
    [
      'Primeiro confirma-se que o nome do servidor existe na internet. Se não existir, a lista não '
          'funciona.',
      'Antes de concluir isso, confirma-se que o próprio aparelho tem internet (perguntando por '
          'nomes conhecidos) e tenta-se outra vez. Assim, uma falha da sua rede não faz as listas '
          'parecerem mortas.',
    ]
  ),
  (
    '2. Entrar na lista',
    [
      'Depois entra-se na lista como um player faria:',
      '• Portal MAC: liga-se ao portal com o endereço MAC e pede-se a lista de canais.',
      '• Xtream: entra-se com o utilizador e a palavra-passe, vê-se o estado da conta e a validade, '
          'e pede-se a lista de canais.',
      '• M3U: descarrega-se a lista.',
      'Uma conta recusada, expirada ou bloqueada é prova de que não funciona. Um erro passageiro '
          'do servidor deixa a lista inconclusiva.',
      'Uma conta sem nenhum canal fica inconclusiva e não se volta a testar logo: daqui a um '
          'minuto continuaria sem canais.',
    ]
  ),
  (
    '3. Procurar os canais de teste',
    [
      'Na lista de canais procuram-se os canais de teste escolhidos nas Definições (RTP 1, '
          'SportTV 1, DAZN 1).',
      'Os nomes variam muito de lista para lista ("RTP 1", "PT: RTP1 HD", "RTP-1"…), por isso '
          'reconhecem-se as várias formas de escrever cada canal, sem confundir com outros parecidos '
          '(a RTP 1 não é a RTP Açores nem a RTP Internacional).',
      'Preferem-se as versões portuguesas e, de cada canal, testam-se no máximo três variantes.',
      'Se um canal de teste não existe na lista, isso conta como prova contra ela.',
    ]
  ),
  (
    '4. Ver se chega imagem',
    [
      'Para cada variante pede-se o endereço do vídeo e lê-se o início do que o servidor envia.',
      'Só conta como imagem se o que chega for mesmo vídeo: uma página de erro, uma mensagem ou '
          'uma resposta vazia não contam.',
      'Se a primeira leitura falhar, espera-se uns segundos e tenta-se uma segunda vez (há '
          'servidores que só respondem à segunda).',
      'Assim que um canal de teste dá imagem, a lista funciona. Se algum ainda estava por testar '
          'quando o tempo acabou, a lista funciona na mesma.',
    ]
  ),
  (
    '5. Tempo limite',
    [
      'Cada leitura de um canal tem um tempo máximo e cada lista tem um tempo máximo no total (os '
          'dois ajustam-se nas Definições).',
      'Se o tempo acabar sem resposta, a lista fica inconclusiva: demorar não prova que esteja '
          'morta.',
    ]
  ),
  (
    '6. Segunda volta para as inconclusivas',
    [
      'Uma lista inconclusiva é testada outra vez, com o dobro do tempo.',
      'Só se repete quando a resposta pode mudar. A segunda volta aproveita o que a primeira já '
          'conseguiu: não volta a pedir a lista de canais e só repete os canais de teste que ficaram '
          'em dúvida.',
      'Se o servidor recusou por excesso de ligações, espera-se um pouco antes de tentar outra vez.',
      'A segunda volta começa assim que o servidor dessa lista fica livre, sem esperar pelas outras '
          'listas.',
      'Se na segunda volta o tempo voltar a acabar, fica o resultado da primeira.',
    ]
  ),
  (
    'Respeito pelos servidores',
    [
      'Verificam-se várias listas ao mesmo tempo (quantas, escolhe-se nas Definições), mas com '
          'cuidado para não sobrecarregar ninguém:',
      '• cada servidor recebe um pedido de cada vez, com um pequeno intervalo entre pedidos;',
      '• o mesmo endereço MAC nunca é usado por duas verificações ao mesmo tempo;',
      '• dá-se preferência a listas de servidores que não estejam já a ser testados;',
      '• se um servidor pedir para abrandar, a verificação espera.',
    ]
  ),
  (
    'A ordem',
    [
      'As listas que já eram inconclusivas na verificação anterior vão à frente e começam logo com '
          'o dobro do tempo, porque costumam ser as mais lentas.',
    ]
  ),
  (
    'Parar e o relatório',
    [
      'Pode sair do ecrã: a verificação continua sozinha.',
      'Ao parar, as listas que já chegaram ao fim ficam com o resultado guardado e aparecem no '
          'relatório. As que estavam na fila ou a meio ficam como estavam.',
    ]
  ),
];

/// "Como é feita a verificação": a lógica, em linguagem simples. Cada secção recebe o foco, para
/// o comando da TV poder descer pelo texto.
class TelaComoVerifica extends StatelessWidget {
  const TelaComoVerifica({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tokens.fundo,
        appBar: AppBar(
          backgroundColor: Tokens.fundo,
          title: const Text('Como é feita a verificação'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(Tokens.e16),
              children: [
                for (final (i, s) in _seccoes.indexed) _SeccaoTexto(s, autofocus: i == 0),
              ],
            ),
          ),
        ),
      );
}

class _SeccaoTexto extends StatefulWidget {
  const _SeccaoTexto(this.seccao, {this.autofocus = false});

  final _Seccao seccao;
  final bool autofocus;

  @override
  State<_SeccaoTexto> createState() => _SeccaoTextoState();
}

class _SeccaoTextoState extends State<_SeccaoTexto> {
  bool _focado = false;

  @override
  Widget build(BuildContext context) {
    final (titulo, texto) = widget.seccao;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.e8),
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (f) => setState(() => _focado = f),
        child: MolduraFoco(
          focado: _focado,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.e12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Tokens.texto)),
              const SizedBox(height: Tokens.e8),
              for (final p in texto)
                Padding(
                  padding: EdgeInsets.only(bottom: Tokens.e4, left: p.startsWith('• ') ? Tokens.e12 : 0),
                  child: Text(p, style: const TextStyle(color: Tokens.texto2, height: 1.4)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
