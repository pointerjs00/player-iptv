# App mais compacta e Verificar simples — design

Origem: feedback do utilizador depois de testar os pacotes dos Ajustes 1 (d2852b5) nos aparelhos, com capturas.
O utilizador pediu para implementar sem mockups.

## Porquê
- «Está tudo demasiado grande»: na TV cabem 2 cartões por linha no Início, 2 listas no Verificar, cada opção
  das Definições é uma caixa grande. A TV fica «overwhelming».
- Botões fora do sítio e demasiados botões (sobretudo no Verificar); para chegar às ações com o comando é
  preciso descer a lista toda.
- Na TV, depois de descer e voltar a subir, o topo do ecrã fica cortado e não se consegue subir mais.
- Na lista aberta quer um campo para filtrar os grupos e outro para os canais (substitui a pesquisa única).
- No Verificar quer filtrar vários estados ao mesmo tempo e selecionar todas as listas desses estados.

## O que muda
1. **Tamanho da interface** (Definições › Imagem e som, primeira opção): «Compacto» (omissão) e «Normal».
   Compacto = toda a interface a 80 % na TV e no Windows (a app desenha-se numa área 1/0,8 maior e é reduzida);
   telemóvel sempre a 100 %. Vale para diálogos e mensagens. Muda logo, sem reiniciar.
2. **Topo nunca cortado:** quando o foco chega ao primeiro controlo focável de uma área com scroll, essa área
   volta ao início (mostra títulos e cabeçalhos por cima). Uma peça global, não ecrã a ecrã.
3. **Regra das ações:** as ações de uma página ficam no topo, à direita do título, num botão «Ações» quando
   são várias; a tecla Menu do comando abre-as de qualquer sítio da página.
4. **Verificar (passo 2):**
   - topo: «← Gestor · Verificar listas», faixa de passos compacta, indicador da verificação;
   - uma linha: pesquisa + chips de estado **de escolha múltipla** com contagens (nenhum ligado = todas);
   - tabela compacta (linhas baixas, 12–14 listas visíveis na TV) com caixa ☐ no cabeçalho que seleciona /
     desseleciona todas as visíveis;
   - um botão «Ações (N)» no topo direito com «Verificar selecionadas», «Verificar todas», «Remover do gestor»;
     a tecla Menu abre-o de qualquer linha;
   - sai a linha «Selecionar:» e sai a barra de baixo; «Ver verificação» passa a ser o indicador da
     verificação no topo (OK nele abre o progresso; «nada a decorrer» quando não há).
5. **Lista aberta:** «Filtrar grupos» no topo da coluna dos grupos e «Pesquisar canais ou número» no topo da
   coluna dos canais; sai a escolha «Tudo · Canais · Grupos» e a lista de grupos encontrados na pesquisa de
   canais. ↑ no primeiro grupo vai ao filtro dos grupos; ↑ no primeiro canal vai à pesquisa dos canais.
   Voltar com texto num campo limpa esse campo.
6. **Compactar os ecrãs grandes:**
   - Início: «Continuar a ver» numa faixa baixa; pesquisa e filtros numa só linha; cartões mais baixos
     (3–4 por linha na TV);
   - Gestor › resumo: cartões baixos (número, rótulo e 2 linhas), sem o texto de rodapé;
   - Gestor › Enviar: linhas da tabela baixas como no Verificar, chips de marcar numa linha;
   - Definições: cada opção é uma linha (título + descrição à esquerda, controlo à direita) com separadores,
     sem caixa à volta.

## Fora do âmbito
Player, cores, o fluxo dos passos do Gestor, o calendário do stbstalker.

## Abordagens
Para o tamanho: (A) escala global da interface — um sítio, tudo proporcional; (B) reduzir tamanhos ecrã a
ecrã — mais controlo, muito mais trabalho e inconsistente. Escolhi A mais compactar os ecrãs onde a
estrutura (não só o tamanho) é o problema. Para o Verificar o utilizador aprovou a proposta em texto.

## Decisões minhas
- 80 % no modo Compacto; o modo Normal fica para quem prefira o tamanho atual.
- A peça do «topo cortado» age só quando não há nada focável acima do foco dentro da mesma área com scroll.
- Indicador no Verificar: com verificação atual ou desta sessão abre o progresso; senão mostra «nada a decorrer».
