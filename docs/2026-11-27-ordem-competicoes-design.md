# Ordem das competições nos Jogos — design curto

## Porquê
Nos Jogos, os blocos de competições aparecem pela ordem fixa do catálogo (`catalogoCompeticoes`).
O utilizador quer pôr primeiro as competições que lhe interessam mais.

## O que se faz
- **Botão «Competições»** no cabeçalho dos Jogos (ícone de taça, ao lado de «Atualizar»; no
  telemóvel também no cabeçalho). Abre um ecrã novo (`TelaCompeticoes`, rota por cima).
- **Ecrã «Competições»**: só as **competições seguidas** (as de Definições › Jogos), pela ordem
  atual, cada uma com o logótipo, o nome e o desporto. Botão **«Reordenar»** no cabeçalho.
- **Modo «Reordenar»** (o botão passa a «Concluído»):
  - comando/teclado: OK pega na competição (fica realçada), CIMA/BAIXO movem-na, OK larga;
    Voltar larga (e, sem nada pegado, sai do modo);
  - toque/rato: cada linha ganha uma pega para arrastar (`ReorderableListView`);
  - cada mudança grava logo (não há «Cancelar»).
- **Jogos**: `agruparPorCompeticao` ordena os blocos por essa ordem.

## Dados
- `PreferenciasJogos` ganha `ordemCompeticoes` (lista de ids, chave `ordem` no
  `preferencias.json`). Sem chave (quem já tem a app): a ordem do catálogo.
- O getter devolve as seguidas pela ordem guardada; as seguidas que não estão na lista vão para o
  fim, pela ordem do catálogo (uma competição que se comece a seguir entra no fim). Deixar de
  seguir não apaga a posição da lista (se voltar a seguir, volta ao mesmo sítio relativo).

## Abordagens consideradas
1. **Modo «Reordenar»** (escolhida): é o pedido («um botão para reordenar»); fora do modo a
   lista fica limpa; funciona com comando, toque e rato.
2. Setas ↑/↓ sempre visíveis em cada linha: mais simples, mas três paragens do foco por linha e
   ecrã carregado; tornava o botão «Reordenar» inútil.

## Fora
- Seguir/deixar de seguir neste ecrã (continua em Definições › Jogos).
- Ordenar os jogos dentro de cada competição (continua pela hora).
- A edição de partilha não tem Jogos: nada muda nela.
