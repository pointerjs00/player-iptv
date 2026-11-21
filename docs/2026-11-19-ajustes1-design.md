# Ajustes 1 ao redesenho — design

Origem: feedback do utilizador depois de testar os pacotes do redesenho (1956e3e) e a escolha das variantes
desenhadas na página «Ajustes 1» do quadro de mockups. Os mockups escolhidos estão copiados para o espaço do
plano (`.superpowers/sdd/2026-11-19-ajustes1-plano/mockups/`); os textos deles são para usar tal como estão,
salvo onde este documento diz outra coisa.

## Porquê

Nos aparelhos, algumas zonas obrigavam a percorrer muito com o comando (filtrar grupos, o filtro «Por
verificar»), o calendário do stbstalker não aceitava OK, e o Gestor misturava a verificação com a marcação
para envio. As Definições não deixavam afinar o ritmo da verificação.

## O que muda

### Ver TV
- **Bug:** o filtro «Por verificar» do Início não recebia o foco com o comando. Tem de se chegar a ele com as
  setas e escolhê-lo com OK, como os outros filtros.
- **Lista aberta (variante C, com uma alteração):** uma só pesquisa no topo para canais e grupos, com a
  escolha «Tudo / Canais / Grupos» (Tudo por omissão). O campo «Filtrar grupos…» no fundo da coluna dos grupos
  desaparece. Com texto na pesquisa, a coluna dos grupos mostra só os grupos encontrados («Grupos · N») e a
  coluna dos canais mostra **todos** os canais encontrados («Canais · N»), com scroll — nunca «+ N canais».
  ↑ no topo de qualquer coluna leva à pesquisa; OK num grupo encontrado limpa a pesquisa e abre o grupo;
  Voltar com texto na pesquisa limpa-a (sem texto, sai como hoje). A procura pelo número do canal mantém-se.

### Gestor
- **Ao entrar (variante A):** nenhum passo aberto. Um resumo com três cartões grandes (Importar, Verificar,
  Enviar ou exportar) com os números de cada um, e uma barra da verificação em curso. Voltar dentro de um
  passo volta ao resumo.
- **Dentro de um passo:** uma faixa com os três passos no topo, para mudar de passo sem voltar ao resumo.
- **Importar · datas do stbstalker (variante C):** o seletor de datas do sistema dá lugar a um calendário no
  próprio ecrã: setas mudam o dia, 1.º OK marca o início, 2.º OK marca o fim, dias depois de hoje não se
  escolhem, «Procurar e juntar» inicia a pesquisa, «Recomeçar» limpa, Voltar sai sem mudar.
- **Passo 2 Verificar (variante A, com alterações):** só tarefas de verificação. Pesquisa, filtros por estado
  com contagens, «Selecionar: Todas as visíveis / Por verificar / Nenhuma», tabela LISTA · ESTADO · MOTIVO ·
  TESTE com caixa de seleção. Barra de ações em baixo **nos azuis da app** (não clara como no mockup) com:
  «Verificar selecionadas», «Verificar todas», «Ver verificação», «Remover do gestor». «Ver verificação»
  mostra o progresso enquanto corre («Ver verificação · 2/5») e fica desativado com «nenhuma verificação»
  quando ainda não houve nenhuma nesta sessão. Abre o ecrã de progresso que já existe.
- **Passo 3 Enviar ou exportar (variante A):** toda a marcação para envio/exportação passa para aqui. À
  esquerda, «Marcar: As que funcionam (N) / + inconclusivas (N) / Todas (N) / Nenhuma» e a lista com caixas; à
  direita, os cartões «Enviar para o Player» e «Exportar para ficheiro» com «Enviar N listas» / «Exportar N
  listas». A pergunta de envio passa a perguntar só como (adicionar ou substituir e o que manter): quais vão já
  está decidido pela marcação.

### Definições › Verificação (variante A)
Linhas com − / + (← → mudam o valor, ↑ ↓ mudam de linha):
- **Listas ao mesmo tempo:** 1 a 20, 8 por omissão. Alimenta o número de verificações em paralelo do Gestor.
- **Tempo limite por lista:** 30 s por omissão (10 a 300, de 10 em 10). Se uma lista não acabar neste tempo,
  fica inconclusiva e passa à seguinte.
- **Tempo por canal:** o valor que já existe (mantém limites e omissão atuais).
- **Canais de teste:** como hoje.
Cada mudança guarda logo e mostra «Guardado · vale para as próximas listas»; com uma verificação a decorrer,
vale para as listas que ainda não começaram.

## Fora do âmbito
Filmes e séries; o player; mudar as cores base; o ecrã de progresso da verificação (só muda o acesso a ele).

## Abordagens
Para o Gestor considerou-se: (A) resumo sem passo, (B) abas com o último passo, (C) abrir no passo sugerido.
O utilizador escolheu A. Para os grupos: filtro no topo (A), tecla Menu (B), pesquisa única (C) — escolheu C,
com a lista de canais completa. Para as datas: setas (A), intervalos rápidos (B), calendário no ecrã (C) —
escolheu C.

## Decisões minhas (o construtor pode contar com elas)
- Barra do passo 2: fundo `Tokens.superficie3`, botões nos estilos da app; «Remover do gestor» em `Tokens.mau`.
- No passo 3 a marcação começa vazia ao abrir a app; mantém-se enquanto a app está aberta.
- No ecrã estreito (sem coluna dos grupos), os grupos encontrados aparecem numa fila de chips por cima dos
  canais.
- O tempo limite por lista vale para cada volta da lista (1.ª volta e reteste), substituindo o limite fixo
  atual por conta.
