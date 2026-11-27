import 'dart:io';

import '../edicao.dart';

/// O que mudou numa versão (as novidades que a app mostra depois de atualizar).
class Novidades {
  const Novidades(this.versao, this.data, this.itens);

  /// "1.0.9" (a `version` do pubspec.yaml, sem o número da compilação).
  final String versao;

  /// O dia do lançamento, "aaaa-mm-dd".
  final String data;

  /// As correções e novidades, em linguagem simples.
  final List<String> itens;
}

/// Todas as versões, a mais recente primeiro. A primeira é a versão da app: ao mudar a versão no
/// pubspec.yaml, junta-se aqui a entrada dela (um teste confirma que batem certo).
const historicoNovidades = <Novidades>[
  Novidades('1.0.26', '2026-11-27', [
    if (!edicaoPartilha) ...[
      'Cópia de segurança: leva também as preferências dos Jogos (equipas favoritas, competições seguidas e a ordem delas).',
      'Jogos: a Liga das Nações e a qualificação do Europeu já não mostram jogos femininos por engano.',
      'Ao abrir, a app avisa quando há uma versão nova publicada.',
    ],
  ]),
  Novidades('1.0.25', '2026-11-27', [
    if (!edicaoPartilha) ...[
      'Jogos: em «Filtros», «Ordenar» deixa ver os jogos numa só lista pela hora, em vez de por competição.',
      'Jogos: em «Competições», escolher uma competição mostra todos os jogos dela, de ontem a daqui a 6 dias, por dia e pela hora.',
      'Jogos: o ecrã «Competições» tem um botão para voltar.',
    ],
  ]),
  Novidades('1.0.24', '2026-11-27', [
    if (!edicaoPartilha) ...[
      'Jogos: o ecrã «Competições» mostra as competições que segues e deixa mudar a ordem delas (com o comando: OK pega, ↑/↓ move, OK larga). Os blocos dos Jogos seguem essa ordem.',
      'Jogos: ténis (ATP e WTA) e basquetebol (NBA e Liga Betclic), com os canais onde dão.',
      'Jogos: os resultados dos jogos a decorrer atualizam-se sozinhos a cada minuto, com o ecrã aberto (não em dados móveis).',
      'Início: a fila «Hoje há jogo» com os jogos de hoje das tuas equipas favoritas; OK abre logo o jogo.',
      'Durante um jogo, «Outras fontes» no player deixa escolher outra lista sem sair.',
      'Jogos: o detalhe mostra o logótipo de cada canal (das tuas listas).',
      'Jogos na TV: a pesquisa por equipa já não abre o teclado sozinha e as setas saem do campo; os botões de cima não perdem o foco.',
      'Jogos no telemóvel: o dia tem uma fila só para ele e «AO VIVO» já não se corta.',
    ],
  ]),
  Novidades('1.0.23', '2026-11-27', [
    if (!edicaoPartilha) ...[
      'Novo ecrã «Jogos»: os jogos das tuas competições (Liga Portugal, Champions, as grandes ligas e '
          'as seleções) e os canais portugueses onde dão, com a hora, o resultado ao vivo e o filtro por dia.',
      '«Onde ver»: para cada canal, as fontes em todas as tuas listas, pela probabilidade de funcionar. '
          '«▶ Ver» abre a melhor e, se não der imagem, passa sozinho à seguinte.',
      'Definições › Jogos: as competições a seguir, as equipas favoritas (ficam em destaque) e a qualidade '
          'preferida.',
    ],
    'No telemóvel: os filtros das listas numa só fila que desliza, e «Ordenar» num botão ao lado da pesquisa.',
    'No telemóvel: o número do canal já não se corta, e o logótipo e o nome ficam ao meio da linha.',
    'No telemóvel: as Estatísticas arrumadas para o ecrã estreito (os totais e os canais mais vistos).',
  ]),
  Novidades('1.0.22', '2026-11-26', [
    'Ver TV: menos texto cortado. Nos cartões das listas o tipo vai ao lado do servidor e as contagens aparecem inteiras; o «Continuar a ver» é mais largo e os favoritos mostram o nome do canal em até 2 linhas.',
  ]),
  Novidades('1.0.21', '2026-11-26', [
    '«Continuar a ver» mais arrumado: a lista, o número e o grupo do canal em etiquetas, e o programa a dar num bloco à parte com «faltam n min» e o progresso.',
    'Os cartões das listas mostram o tipo, os canais e os grupos em etiquetas, e o servidor numa linha própria.',
    'Ver TV: a programação de um canal só se pede com o foco parado nele 0,7 s (a descer depressa não se pede nada).',
  ]),
  Novidades('1.0.20', '2026-11-26', [
    'Ver TV: «A tua semana» mostra as horas vistas, um gráfico dos últimos 7 dias e os canais mais vistos; '
        'abre as Estatísticas completas (30 dias, por dia da semana e por hora).',
    'O tempo de visualização fica só neste aparelho e conta só a reprodução a sério. Desliga-se ou apaga-se '
        'em Definições › Imagem e som.',
    '«Continuar a ver» mostra o programa a dar e o progresso dele.',
    'Início mais limpo: o estado das listas mais discreto, os filtros com a contagem e os favoritos com o '
        'logótipo do canal.',
  ]),
  Novidades('1.0.19', '2026-11-26', [
    'Letra nova em toda a app: Inter no texto e Space Grotesk nos títulos e nos números grandes.',
    'Gestor: ao mudar de passo, o conteúdo já não salta (a barra de cima tem sempre a mesma altura).',
  ]),
  Novidades('1.0.18', '2026-11-26', [
    'Novo visual: azul profundo, cartões e painéis escuros e azul elétrico, com um fundo de faixas de luz.',
    'O foco do comando tem agora uma mira: quatro cantos que se fecham sobre o que está escolhido.',
    'Animações mais suaves ao mudar de ecrã e de foco (desligadas com «reduzir movimento»).',
    'Barra lateral mais estreita, só com os ícones: sobra mais espaço para as listas e os canais.',
    'Ver TV: o programa a dar num painel próprio, com o ponto do direto a pulsar.',
    'Ver TV na TV: numa lista enorme, o cabeçalho dos canais já não sai do ecrã enquanto se ordena.',
  ]),
  Novidades('1.0.17', '2026-11-25', [
    'Ver TV: «A seguir» já não repete um programa que está dentro do que está a dar.',
    'Os sites com certificados da nova raiz da GoDaddy (de 2025) já não dão «falha na ligação segura» '
        'no Windows nem em aparelhos Android antigos.',
    if (!edicaoPartilha) ...[
      'Gestor › Importar › Listas do Telegram: os canais ficam guardados, com favoritos (primeiro na lista) '
          'e «Todos os favoritos», que procura em todos de uma vez.',
      'Gestor › Importar › Listas de um site: além do stbstalker, qualquer site. Nos blogs Blogger e '
          'WordPress lêem-se os posts entre as datas; noutros, a página do endereço.',
    ],
  ]),
  Novidades('1.0.16', '2026-11-23', [
    'Ver TV: programação (EPG) nas listas Xtream e nos portais MAC. Na TV e no computador, uma coluna '
        'à direita mostra o canal com o foco, o programa a dar (com o progresso e a descrição) e os '
        'seguintes.',
    'Ver TV: a pesquisa também encontra os canais pelo programa a dar ou pelo seguinte.',
    'No telemóvel: «Agora: …» por baixo de cada canal; o toque longo abre os detalhes, com «Ver» e '
        'os favoritos.',
    'No telemóvel: Definições › Ligação › «Poupar dados móveis». Com dados móveis, a app pergunta '
        'antes de descarregar a programação, carregar canais ou verificar listas.',
  ]),
  Novidades('1.0.15', '2026-11-23', [
    'Novidades: cada versão mostra a data em que saiu.',
  ]),
  Novidades('1.0.14', '2026-11-23', [
    if (!edicaoPartilha)
      'Gestor › Importar: novo «Listas do Telegram», que junta as listas publicadas num canal público '
          '(por omissão o @michelstv4) entre as datas escolhidas.',
    'No telemóvel: as barras do volume e o deslize na lateral do ecrã mudam o volume do sistema e '
        'acompanham as teclas do telefone. Saiu a opção «Volume inicial do sistema».',
    'No telemóvel: o motor do player passa a ser o mpv por omissão.',
    'No telemóvel: ao exportar (Accounts.json ou a cópia de segurança) escolhe-se a pasta onde gravar.',
    'Ao desinstalar, a app já não deixa as listas nem o «Continuar a ver» numa cópia de segurança do '
        'Android.',
  ]),
  Novidades('1.0.13', '2026-11-23', [
    'Em inglês: o progresso da verificação («Testing channel 2 of 3») e o das páginas ao carregar '
        'um portal voltam a aparecer, e as últimas frases que ficavam em português foram traduzidas.',
  ]),
  Novidades('1.0.12', '2026-11-22', [
    'Definições › Idioma · Language: a app pode ficar em inglês (English). Muda logo, sem reiniciar.',
    'Ao ver um canal: ao carregar em OK na barra do volume, ela dá um pulo e mostra as setas ‹ › '
        'enquanto se ajusta.',
  ]),
  Novidades('1.0.11', '2026-11-22', [
    'Gestor › Verificar: quando a verificação acaba, as listas selecionadas que deixaram de '
        'aparecer com os filtros ativos saem da seleção (o "Ações (N)" conta só as que se veem).',
  ]),
  Novidades('1.0.10', '2026-11-22', [
    'Ver TV: → num grupo vai sempre ao primeiro canal desse grupo.',
    'Ver TV: sempre que o grupo muda (também ao esconder o grupo aberto), a lista dos canais volta '
        'ao topo.',
    'Gestor › Nova lista: os campos de cada tipo aparecem logo ao passar pelo botão do tipo, sem '
        'ser preciso carregar nele.',
  ]),
  Novidades('1.0.9', '2026-11-22', [
    'Gestor: no passo "Verificar", o botão da atividade abre a Atividade com todos os relatórios, '
        'como nos outros passos.',
    'Atividade: todos os cartões têm "Ver detalhe", também o de uma verificação parada.',
    'Durante a verificação, o "Parar" fica junto do indicador "A verificar".',
    'Ver TV: ao escolher um grupo, os canais aparecem a partir do primeiro.',
    'Novidades: este resumo aparece depois de cada atualização e pode ser visto de novo em '
        'Definições › Sobre e licenças.',
  ]),
  Novidades('1.0.8', '2026-11-22', [
    'Gestor: "Parar" no passo "Verificar", na barra de cima e no menu Ações.',
    'Ao ver um canal: barra de volume com botão de silêncio, em todas as plataformas. No comando, OK e '
        'depois ← → mudam o volume.',
  ]),
  Novidades('1.0.7', '2026-11-22', [
    'Gestor: o "i" da verificação fica no canto da barra de cima.',
    'Atividade: depois de parar ou terminar, a verificação fica com o resumo e o relatório.',
    'As janelas de confirmação ficaram mais estreitas e fáceis de ler.',
  ]),
  Novidades('1.0.6', '2026-11-22', [
    'Parar a verificação pede confirmação e mostra o relatório das listas que chegaram ao fim.',
    'Novo ecrã "Como é feita a verificação" (o botão "i").',
    'O passo 3 do Gestor passa a chamar-se "Exportar".',
    '"Adicionar lista": Portal MAC, Xtream (link ou servidor e conta), lista M3U ou várias coladas.',
    'Definições de verificação na TV: carregar em OK para mudar um valor; ← vai ao menu lateral.',
  ]),
  Novidades('1.0.5', '2026-11-22', [
    'A verificação das listas inconclusivas ficou mais rápida e já não atrasa as outras.',
  ]),
];

/// A versão da app ("1.0.9").
/// A data do lançamento para mostrar: "22/11/2026".
String dataNovidades(Novidades n) {
  final d = DateTime.parse(n.data);
  String dois(int x) => x.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year}';
}

String get versaoApp => historicoNovidades.first.versao;

/// As versões com alguma novidade nesta edição (na de partilha, uma versão só com novidades dos
/// Jogos fica vazia).
List<Novidades> versoesComNovidades([List<Novidades> h = historicoNovidades]) => [
      for (final n in h)
        if (n.itens.isNotEmpty) n,
    ];

/// O aviso depois de atualizar: as novidades da versão da app, ou null se nesta edição não tem nenhuma.
Novidades? novidadesDoAviso([List<Novidades> h = historicoNovidades]) => h.first.itens.isEmpty ? null : h.first;

/// O ficheiro com a última versão cujas novidades se mostraram.
const ficheiroNovidadesVistas = 'novidades_vistas.txt';

/// As novidades da versão atual estão por ver? Só uma vez por versão: marca-as logo como vistas.
/// Numa instalação nova (`instalacaoNova`: sem listas e sem registo) não há nada a mostrar.
Future<bool> novidadesPorVer(Directory pasta, {required bool instalacaoNova}) async {
  final f = File('${pasta.path}${Platform.pathSeparator}$ficheiroNovidadesVistas');
  String? vista;
  try {
    if (await f.exists()) vista = (await f.readAsString()).trim();
  } on FileSystemException {
    vista = null;
  }
  if (vista == versaoApp) return false;
  try {
    await f.writeAsString(versaoApp, flush: true);
  } on FileSystemException {
    // sem gravar, mostra-se na mesma (na próxima abertura volta a aparecer)
  }
  return vista != null || !instalacaoNova;
}
