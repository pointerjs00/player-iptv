import '../edicao.dart';

/// As traduções inglesas: chave = o texto português (como está no código, com {0}, {1}…).
const textosIngles = <String, String>{
  'Adição':
      'Added',
  'Pela ordem em que foram adicionadas':
      'In the order they were added',
  'Nome A–Z':
      'Name A–Z',
  'Pelo nome da lista':
      'By list name',
  'Estado':
      'Status',
  'As que funcionam primeiro':
      'Working ones first',
  'Verificação':
      'Check',
  'A verificada há menos tempo primeiro':
      'Most recently checked first',
  'Validade':
      'Expiry',
  'A que acaba mais tarde primeiro':
      'Latest expiry first',
  'a lista já não existe':
      'the list no longer exists',
  'já existe outra lista com esta conta':
      'another list with this account already exists',
  'O ficheiro não é uma cópia de segurança: não tem JSON válido.':
      'The file is not a backup: it has no valid JSON.',
  'Este ficheiro não é uma cópia de segurança do {0}.':
      'This file is not a {0} backup.',
  'A cópia de segurança não indica a versão e não se pode importar.':
      'The backup does not state its version and cannot be imported.',
  'Esta cópia foi criada por uma versão mais recente da app. Atualize a app para a importar.':
      'This backup was created by a newer version of the app. Update the app to import it.',
  'A cópia de segurança está estragada: as listas {0} não se conseguem ler.':
      'The backup is damaged: the {0} lists cannot be read.',
  'A cópia de segurança está estragada: a lista {0} {1} não se consegue ler.':
      'The backup is damaged: list {0} {1} cannot be read.',
  'A cópia de segurança está vazia: não tem listas nem de Ver TV nem do Gestor.':
      'The backup is empty: it has no lists in Watch TV or in the Manager.',
  'A importação falhou ({0}) e não foi possível repor tudo: confira as listas e as definições.':
      'The import failed ({0}) and not everything could be restored: check the lists and the settings.',
  'Não foi possível importar ({0}).':
      'Could not import ({0}).',
  'Sem permissão para guardar nas Transferências. Permita o acesso ao armazenamento e tente de novo.':
      'No permission to save to Downloads. Allow storage access and try again.',
  'Não foi possível guardar o ficheiro{0}.':
      'Could not save the file{0}.',
  'Não foi possível guardar o ficheiro: {0}':
      'Could not save the file: {0}',
  'O Android não devolveu o destino do ficheiro.':
      'Android did not return the file destination.',
  'Transferências/{0}':
      'Downloads/{0}',
  'Guardar {0}':
      'Save {0}',
  'Gestor › Verificar: quando a verificação acaba, as listas selecionadas que deixaram de aparecer com os filtros ativos saem da seleção (o "Ações (N)" conta só as que se veem).':
      'Manager › Check: when the check finishes, selected lists that no longer appear with the active filters leave the selection ("Actions (N)" only counts the visible ones).',
  'Ver TV: → num grupo vai sempre ao primeiro canal desse grupo.':
      'Watch TV: → on a group always goes to the first channel of that group.',
  'Ver TV: sempre que o grupo muda (também ao esconder o grupo aberto), a lista dos canais volta ao topo.':
      'Watch TV: whenever the group changes (also when hiding the open group), the channel list goes back to the top.',
  'Gestor › Nova lista: os campos de cada tipo aparecem logo ao passar pelo botão do tipo, sem ser preciso carregar nele.':
      'Manager › New list: the fields of each type appear as soon as you move over the type button, without having to press it.',
  'Gestor: no passo "Verificar", o botão da atividade abre a Atividade com todos os relatórios, como nos outros passos.':
      'Manager: in the "Check" step, the activity button opens Activity with all the reports, as in the other steps.',
  'Atividade: todos os cartões têm "Ver detalhe", também o de uma verificação parada.':
      'Activity: every card has "See details", including the one for a stopped check.',
  'Durante a verificação, o "Parar" fica junto do indicador "A verificar".':
      'During a check, "Stop" sits next to the "Checking" indicator.',
  'Ver TV: ao escolher um grupo, os canais aparecem a partir do primeiro.':
      'Watch TV: when choosing a group, the channels start from the first one.',
  'Novidades: este resumo aparece depois de cada atualização e pode ser visto de novo em Definições › Sobre e licenças.':
      'What\'s new: this summary appears after each update and can be seen again in Settings › About and licences.',
  'Gestor: "Parar" no passo "Verificar", na barra de cima e no menu Ações.':
      'Manager: "Stop" in the "Check" step, in the top bar and in the Actions menu.',
  'Ao ver um canal: barra de volume com botão de silêncio, em todas as plataformas. No comando, OK e depois ← → mudam o volume.':
      'While watching a channel: volume bar with a mute button, on every platform. On the remote, OK and then ← → change the volume.',
  'Gestor: o "i" da verificação fica no canto da barra de cima.':
      'Manager: the check\'s "i" sits in the corner of the top bar.',
  'Atividade: depois de parar ou terminar, a verificação fica com o resumo e o relatório.':
      'Activity: after stopping or finishing, the check keeps its summary and report.',
  'As janelas de confirmação ficaram mais estreitas e fáceis de ler.':
      'Confirmation dialogs are narrower and easier to read.',
  'Parar a verificação pede confirmação e mostra o relatório das listas que chegaram ao fim.':
      'Stopping a check asks for confirmation and shows the report of the lists that finished.',
  'Novo ecrã "Como é feita a verificação" (o botão "i").':
      'New "How the check works" screen (the "i" button).',
  'O passo 3 do Gestor passa a chamar-se "Exportar".':
      'Manager step 3 is now called "Export".',
  '"Adicionar lista": Portal MAC, Xtream (link ou servidor e conta), lista M3U ou várias coladas.':
      '"Add list": MAC portal, Xtream (link or server and account), M3U list or several pasted.',
  'Definições de verificação na TV: carregar em OK para mudar um valor; ← vai ao menu lateral.':
      'Check settings on TV: press OK to change a value; ← goes to the side menu.',
  'A verificação das listas inconclusivas ficou mais rápida e já não atrasa as outras.':
      'Checking inconclusive lists is faster and no longer delays the others.',
  'Ajustar':
      'Fit',
  'Preencher':
      'Fill',
  'Esticar':
      'Stretch',
  'Automático':
      'Automatic',
  'Ligado':
      'On',
  'Desligado':
      'Off',
  'Compacto':
      'Compact',
  'Armazenamento':
      'Storage',
  'Grava o canal no armazenamento interno para poderes recuar e pausar. Apagado ao mudar de canal.':
      'Records the channel to internal storage so you can rewind and pause. Deleted when the channel changes.',
  'Memória':
      'Memory',
  'Guarda os últimos minutos em memória (menos tempo, sem usar o armazenamento).':
      'Keeps the last minutes in memory (less time, without using storage).',
  'Sem recuo no direto.':
      'No rewind in live TV.',
  'não há espaço no armazenamento para continuar a gravar':
      'there is no storage space left to keep recording',
  'não foi possível gravar no armazenamento':
      'could not record to storage',
  'o servidor fechou a ligação':
      'the server closed the connection',
  'Pouco espaço: o recuo fica em memória (cerca de 2 min em HD)':
      'Low space: rewind stays in memory (about 2 min in HD)',
  'Pouco espaço: o recuo fica com {0} MB':
      'Low space: rewind is limited to {0} MB',
  'o ficheiro não é JSON válido':
      'the file is not valid JSON',
  'o histórico não é JSON válido':
      'the history is not valid JSON',
  'o ficheiro não é um histórico do verificador':
      'the file is not a checker history',
  '{0}: falta o Address ou o Mac':
      '{0}: Address or Mac is missing',
  '{0}: não foi encontrada nenhuma lista':
      '{0}: no list was found',
  'Nenhum post publicado {0}.':
      'No post published {0}.',
  'Não foi possível abrir o player ({0}).':
      'Could not open the player ({0}).',
  'A janela do player não abriu a tempo. Tente de novo.':
      'The player window did not open in time. Try again.',
  'A app já está aberta noutra janela. Feche esta e use a outra.':
      'The app is already open in another window. Close this one and use the other.',
  'Não foi possível ler as listas guardadas ({0}). Feche outros programas que as possam ter abertas e abra a app de novo.':
      'Could not read the saved lists ({0}). Close other programs that may have them open and open the app again.',
  'Fechar':
      'Close',
  'servidor recusou o acesso à lista ({0})':
      'the server refused access to the list ({0})',
  'o endereço não devolveu uma lista M3U':
      'the address did not return an M3U list',
  'a ler os canais':
      'reading the channels',
  'sem limite':
      'no limit',
  'a ligar ao portal ({0})':
      'connecting to the portal ({0})',
  'o portal respondeu sem token':
      'the portal replied without a token',
  'portal não encontrado':
      'portal not found',
  'não foi possível entrar no portal: {0}':
      'could not log in to the portal: {0}',
  'a pedir as categorias':
      'requesting the categories',
  'a pedir a lista de canais':
      'requesting the channel list',
  'não foi possível listar os canais ({0})':
      'could not list the channels ({0})',
  'o portal não devolveu canais':
      'the portal returned no channels',
  'conta expirada em {0}':
      'account expired on {0}',
  'a pedir os canais · página {0}{1}':
      'requesting the channels · page {0}{1}',
  'o portal não devolveu o link do canal':
      'the portal did not return the channel link',
  'a entrar na conta':
      'logging in to the account',
  'o servidor não respondeu como um painel Xtream':
      'the server did not reply like an Xtream panel',
  'resposta do servidor sem estado de autenticação':
      'server reply without authentication status',
  'autenticação recusada':
      'authentication refused',
  'a pedir os canais':
      'requesting the channels',
  'o servidor não devolveu a lista de canais':
      'the server did not return the channel list',
  'acesso recusado ({0})':
      'access refused ({0})',
  'não encontrado (404)':
      'not found (404)',
  'o painel recusa a ligação (456) — MAC em uso noutro aparelho?':
      'the panel refuses the connection (456) — MAC in use on another device?',
  'erro do servidor ({0})':
      'server error ({0})',
  'o servidor não respondeu a tempo':
      'the server did not reply in time',
  'a resposta do servidor é grande demais':
      'the server reply is too large',
  'falha na ligação segura (certificado ou TLS)':
      'secure connection failed (certificate or TLS)',
  'não foi possível ligar ao servidor':
      'could not connect to the server',
  'a ligação foi cortada pelo servidor':
      'the connection was cut by the server',
  'endereço ou resposta inválidos':
      'invalid address or reply',
  'não foi possível ler o ficheiro':
      'could not read the file',
  'falha inesperada':
      'unexpected failure',
  'Parada antes de acabar.':
      'Stopped before finishing.',
  'Não foi encontrada nenhuma lista.':
      'No list was found.',
  '1 lista nova':
      '1 new list',
  '{0} listas novas':
      '{0} new lists',
  '1 já existia':
      '1 already existed',
  '{0} já existiam':
      '{0} already existed',
  ' Com problemas: {0}':
      ' With problems: {0}',
  'Escolher listas':
      'Choose lists',
  'Portal MAC':
      'MAC portal',
  'Xtream (link)':
      'Xtream (link)',
  'Xtream (servidor e conta)':
      'Xtream (server and account)',
  'Lista M3U':
      'M3U list',
  'Várias (colar)':
      'Several (paste)',
  'Escreva o endereço do portal (por exemplo http://portal.com:8080/c/).':
      'Enter the portal address (for example http://portal.com:8080/c/).',
  'O MAC tem de ter 6 pares, como 00:1A:79:12:34:56.':
      'The MAC must have 6 pairs, like 00:1A:79:12:34:56.',
  'O link tem de ter o utilizador e a palavra-passe (…/get.php?username=…&password=…).':
      'The link must include the username and password (…/get.php?username=…&password=…).',
  'Escreva o endereço do servidor (por exemplo http://servidor.com:8080).':
      'Enter the server address (for example http://server.com:8080).',
  'Escreva o utilizador e a palavra-passe.':
      'Enter the username and password.',
  'Escreva o endereço da lista M3U.':
      'Enter the M3U list address.',
  'Mostrar o grupo':
      'Show the group',
  'Esconder o grupo':
      'Hide the group',
  'Ordem da lista':
      'List order',
  'Ordenar A–Z':
      'Sort A–Z',
  'Ocultar grupos escondidos':
      'Hide hidden groups',
  'Mostrar grupos escondidos ({0})':
      'Show hidden groups ({0})',
  'Vistos há pouco':
      'Recently watched',
  'O último canal visto já não está nesta lista.':
      'The last channel watched is no longer in this list.',
  'Não foi possível guardar ({0}).':
      'Could not save ({0}).',
  'Grupo "{0}" escondido':
      'Group "{0}" hidden',
  'Desfazer':
      'Undo',
  'Não foi possível atualizar: {0}':
      'Could not update: {0}',
  'carregamento cancelado':
      'loading cancelled',
  'A carregar os canais':
      'Loading the channels',
  'A atualizar os canais':
      'Updating the channels',
  '‹ Início':
      '‹ Home',
  'Opções dos canais':
      'Channel options',
  'Ordem: {0}':
      'Order: {0}',
  'Grupos escondidos: {0}':
      'Hidden groups: {0}',
  'Atualizar a lista de canais':
      'Update the channel list',
  'Mais opções':
      'More options',
  'Ordem: da lista':
      'Order: as in list',
  'Ordem: A–Z':
      'Order: A–Z',
  'Atualizar canais':
      'Update channels',
  'Voltar ao Início':
      'Back to Home',
  'Ainda não foi verificada':
      'Not checked yet',
  'Verificada {0}{1}':
      'Checked {0}{1}',
  'da cache · {0}':
      'from cache · {0}',
  'Não foi possível abrir a lista: {0}':
      'Could not open the list: {0}',
  'Tentar de novo':
      'Try again',
  'Todos':
      'All',
  'Todos os canais':
      'All channels',
  'Grupo: {0}':
      'Group: {0}',
  'Pesquisar grupos':
      'Search groups',
  'Nenhum grupo':
      'No group',
  'Pesquisar canais ou número':
      'Search channels or number',
  'Pesquisar em {0}':
      'Search in {0}',
  'Filtrar grupos':
      'Filter groups',
  'Nenhum canal.':
      'No channels.',
  'Tirar dos favoritos':
      'Remove from favourites',
  'Pôr nos favoritos':
      'Add to favourites',
  '{0} está nos favoritos':
      '{0} is in favourites',
  '{0} saiu dos favoritos':
      '{0} left favourites',
  'Escolher a cópia de segurança':
      'Choose the backup',
  'O ficheiro é demasiado grande para ser uma cópia de segurança.':
      'The file is too large to be a backup.',
  'Imagem e som':
      'Picture and sound',
  'Ligação':
      'Connection',
  'Cópia de segurança':
      'Backup',
  'Sobre e licenças':
      'About and licences',
  'Guardado':
      'Saved',
  'Guardado · vale para as próximas listas':
      'Saved · applies to the next lists',
  'Guardado · vale a partir do próximo canal':
      'Saved · applies from the next channel',
  'só no motor mpv':
      'mpv engine only',
  'Exportação cancelada.':
      'Export cancelled.',
  'Cópia guardada em {0}':
      'Backup saved to {0}',
  'Não foi possível exportar: {0}':
      'Could not export: {0}',
  'Cópia importada: {0} em Ver TV, {1} no Gestor{2}{3}.':
      'Backup imported: {0} in Watch TV, {1} in the Manager{2}{3}.',
  '{0} Nada foi alterado.':
      '{0} Nothing was changed.',
  'Não foi possível importar ({0}). Nada foi alterado.':
      'Could not import ({0}). Nothing was changed.',
  'Importar cópia de segurança':
      'Import backup',
  'A cópia tem {0} listas de Ver TV e {1} do Gestor{2}.\n\nJuntar: acrescenta o que falta, sem duplicar, e une favoritos e resultados.\nSubstituir: apaga as listas atuais e fica só com as da cópia.':
      'The backup has {0} Watch TV lists and {1} Manager lists{2}.\n\nMerge: adds what is missing, without duplicates, and merges favourites and results.\nReplace: deletes the current lists and keeps only the ones in the backup.',
  'Cancelar':
      'Cancel',
  'Substituir tudo':
      'Replace everything',
  'Juntar':
      'Merge',
  'Tamanho da interface':
      'Interface size',
  'Compacto mostra mais em cada ecrã (80 % na TV e no Windows).':
      'Compact shows more on each screen (80 % on TV and Windows).',
  'Motor do player':
      'Playback engine',
  'O ExoPlayer é o mais fluido. Se um canal não abrir nele, abre sozinho no mpv.':
      'ExoPlayer is the smoothest. If a channel does not open in it, it opens in mpv on its own.',
  'Modo túnel':
      'Tunnel mode',
  'Só em aparelhos que o suportam. Pode ajudar a fluidez; se a imagem falhar, desliga.':
      'Only on devices that support it. May help smoothness; if the picture fails, turn it off.',
  'Desentrelaçamento':
      'Deinterlacing',
  'Evita riscas nos canais entrelaçados. Automático só o liga quando é preciso.{0}':
      'Avoids stripes on interlaced channels. Automatic only turns it on when needed.{0}',
  'Descodificação por hardware':
      'Hardware decoding',
  'Mais leve. Desliga se a imagem falhar.':
      'Lighter. Turn it off if the picture fails.',
  'Ajustar a taxa do ecrã ao canal':
      'Match the screen refresh rate to the channel',
  'Evita soluços nas imagens (Android TV)':
      'Avoids stutter in the picture (Android TV)',
  'Descodificação no Android':
      'Decoding on Android',
  'Direta é a mais leve. Compatível serve se o direto mostrar ecrã preto ou cores erradas.':
      'Direct is the lightest. Compatible helps if live TV shows a black screen or wrong colours.',
  'Formato da imagem':
      'Picture format',
  'Vale para todos os canais':
      'Applies to all channels',
  'Volume ao abrir':
      'Volume on opening',
  'O volume com que cada canal começa.':
      'The volume each channel starts with.',
  'Recuar no direto':
      'Rewind in live TV',
  'Espaço reservado':
      'Reserved space',
  'Quanto do armazenamento interno se usa, no máximo.':
      'The most internal storage that is used.',
  'Listas ao mesmo tempo':
      'Lists at the same time',
  'Quantas listas se verificam em simultâneo (1 a 20). Mais é mais rápido, mas pesa na rede.':
      'How many lists are checked at once (1 to 20). More is faster, but loads the network.',
  'Tempo limite por lista':
      'Time limit per list',
  'Se uma lista não acabar neste tempo, fica inconclusiva e passa à seguinte.':
      'If a list does not finish in this time, it becomes inconclusive and the next one starts.',
  'Tempo por canal':
      'Time per channel',
  'Quanto se espera por cada canal de teste.':
      'How long to wait for each test channel.',
  'Canais de teste':
      'Test channels',
  'A lista funciona se um deles abrir.':
      'The list works if one of them opens.',
  'Escolha pelo menos um canal.':
      'Choose at least one channel.',
  'Com uma verificação a decorrer, as mudanças valem para as próximas listas.{0}':
      'With a check running, changes apply to the next lists.{0}',
  'User-agent':
      'User agent',
  'Opcional: nos pedidos das listas M3U e Xtream (o Stalker mantém o da box MAG).':
      'Optional: used in M3U and Xtream list requests (Stalker keeps the MAG box one).',
  'User-agent personalizado':
      'Custom user agent',
  'Em branco: o do VLC':
      'Blank: VLC\'s',
  'Repor o por omissão':
      'Restore the default',
  'Exportar e importar':
      'Export and import',
  'Guarda as listas, favoritos, resultados, o Gestor e as definições num ficheiro .json. O ficheiro inclui as credenciais das listas: guarde-o em local seguro.':
      'Saves the lists, favourites, results, the Manager and the settings to a .json file. The file includes the list credentials: keep it somewhere safe.',
  'Exportar cópia':
      'Export backup',
  'Importar cópia':
      'Import backup',
  'Novidades':
      'What\'s new',
  'O que mudou em cada versão. Esta é a {0}.':
      'What changed in each version. This is {0}.',
  'Ver novidades':
      'See what\'s new',
  'Licenças':
      'Licences',
  'O player usa o mpv e o ffmpeg (GPLv3).':
      'The player uses mpv and ffmpeg (GPLv3).',
  'Ver licenças':
      'See licences',
  'Definições':
      'Settings',
  'Voltar':
      'Back',
  'Funciona':
      'Works',
  'Inconclusiva':
      'Inconclusive',
  'Não funciona':
      'Does not work',
  'Por verificar':
      'Not checked',
  'Menu: {0}':
      'Menu: {0}',
  'Mês anterior':
      'Previous month',
  'Mês seguinte':
      'Next month',
  'Escolhe o início e o fim':
      'Choose the start and the end',
  'De':
      'From',
  'Até':
      'To',
  '1.º OK marca o início, 2.º OK marca o fim. Os dias depois de hoje não se escolhem.':
      '1st OK marks the start, 2nd OK marks the end. Days after today cannot be chosen.',
  'Procurar e juntar':
      'Search and add',
  'Recomeçar':
      'Start over',
  'sair sem mudar':
      'leave without changing',
  'Nada a decorrer':
      'Nothing running',
  '{0} funcionam, {1} não{2}':
      '{0} work, {1} don\'t{2}',
  'Fechar a atividade':
      'Close activity',
  'Atividade':
      'Activity',
  'Nada a decorrer.':
      'Nothing running.',
  'Podes fechar este painel e continuar a usar a app. Cada tarefa avisa quando termina.':
      'You can close this panel and keep using the app. Each task tells you when it finishes.',
  'Verificação das listas':
      'List check',
  'Ver detalhe':
      'See details',
  'Parar':
      'Stop',
  '{0} às {1}':
      '{0} at {1}',
  'Nenhuma lista chegou ao fim.':
      'No list finished.',
  'Terminada':
      'Finished',
  'Falhou':
      'Failed',
  'Cancelada':
      'Cancelled',
  'Durou {0}':
      'Took {0}',
  '{0} · OK marca/desmarca uma lista':
      '{0} · OK ticks/unticks a list',
  'Marcar listas':
      'Tick lists',
  'Funcionam':
      'Working',
  'Inconclusivas':
      'Inconclusive',
  'Não funcionam':
      'Not working',
  'Todas':
      'All',
  'Nenhuma':
      'None',
  'Marcar:':
      'Tick:',
  'Para onde':
      'Where to',
  'Enviar {0}':
      'Send {0}',
  'Enviar ({0})':
      'Send ({0})',
  'Exportar {0}':
      'Export {0}',
  'Exportar ({0})':
      'Export ({0})',
  'Enviar para Ver TV':
      'Send to Watch TV',
  'Adicionar às que já lá estão, ou substituir (escolhes a seguir).':
      'Add to the ones already there, or replace them (you choose next).',
  'Exportar para ficheiro':
      'Export to file',
  'Accounts.json (sfvip) ou .ini num zip (Stalker). O ficheiro leva os dados de acesso.':
      'Accounts.json (sfvip) or .ini in a zip (Stalker). The file carries the access details.',
  'há {0} min':
      '{0} min ago',
  'há {0} h':
      '{0} h ago',
  'há {0} dias':
      '{0} days ago',
  'O Gestor está vazio':
      'The Manager is empty',
  'Verificar selecionadas':
      'Check selected',
  'Verificar todas':
      'Check all',
  'Parar a verificação':
      'Stop the check',
  'Remover do gestor':
      'Remove from the manager',
  'Ainda não há listas. Comece pelo passo 1: importe as listas.':
      'No lists yet. Start with step 1: import the lists.',
  'Nenhuma lista com estes estados.':
      'No list with these statuses.',
  'Ações ({0})':
      'Actions ({0})',
  'Pesquisar listas…':
      'Search lists…',
  'Selecionar as visíveis':
      'Select the visible ones',
  'Selecionar todas as visíveis':
      'Select all visible',
  'Na fila':
      'Queued',
  'O que a verificação quer saber':
      'What the check wants to know',
  'Se cada lista dá mesmo imagem. Não basta o servidor responder: a verificação abre canais de teste e confirma que chega vídeo a sério.':
      'Whether each list really gives a picture. The server answering is not enough: the check opens test channels and confirms that real video arrives.',
  'No fim, cada lista fica num de três estados:':
      'In the end, each list is in one of three statuses:',
  '• Funciona: pelo menos um canal de teste deu imagem.':
      '• Works: at least one test channel gave a picture.',
  '• Não funciona: há uma prova de que a lista não serve (por exemplo, a conta foi recusada, expirou, o endereço já não existe ou os canais de teste não existem nela).':
      '• Does not work: there is proof that the list is no good (for example, the account was refused, expired, the address no longer exists or the test channels do not exist in it).',
  '• Inconclusiva: não deu imagem, mas também não há prova de que esteja morta (o servidor estava lento, cortou a ligação, recusou por excesso de ligações…). Nunca se marca uma lista como "não funciona" só porque demorou.':
      '• Inconclusive: no picture, but no proof that it is dead either (the server was slow, cut the connection, refused because of too many connections…). A list is never marked as "does not work" just because it was slow.',
  '1. O endereço existe?':
      '1. Does the address exist?',
  'Primeiro confirma-se que o nome do servidor existe na internet. Se não existir, a lista não funciona.':
      'First it is confirmed that the server name exists on the internet. If it does not, the list does not work.',
  'Antes de concluir isso, confirma-se que o próprio aparelho tem internet (perguntando por nomes conhecidos) e tenta-se outra vez. Assim, uma falha da sua rede não faz as listas parecerem mortas.':
      'Before concluding that, it is confirmed that the device itself has internet (by asking for well-known names) and it is tried again. That way, a failure of your network does not make the lists look dead.',
  '2. Entrar na lista':
      '2. Logging in to the list',
  'Depois entra-se na lista como um player faria:':
      'Then the check logs in to the list as a player would:',
  '• Portal MAC: liga-se ao portal com o endereço MAC e pede-se a lista de canais.':
      '• MAC portal: it connects to the portal with the MAC address and asks for the channel list.',
  '• Xtream: entra-se com o utilizador e a palavra-passe, vê-se o estado da conta e a validade, e pede-se a lista de canais.':
      '• Xtream: it logs in with the username and password, reads the account status and expiry, and asks for the channel list.',
  'Uma conta recusada, expirada ou bloqueada é prova de que não funciona. Um erro passageiro do servidor deixa a lista inconclusiva.':
      'A refused, expired or blocked account is proof that it does not work. A temporary server error leaves the list inconclusive.',
  'Uma conta sem nenhum canal fica inconclusiva e não se volta a testar logo: daqui a um minuto continuaria sem canais.':
      'An account without any channel is inconclusive and is not tested again right away: a minute later it would still have no channels.',
  '3. Procurar os canais de teste':
      '3. Looking for the test channels',
  'Na lista de canais procuram-se os canais de teste escolhidos nas Definições (RTP 1, SportTV 1, DAZN 1).':
      'The channel list is searched for the test channels chosen in Settings (RTP 1, SportTV 1, DAZN 1).',
  'Os nomes variam muito de lista para lista ("RTP 1", "PT: RTP1 HD", "RTP-1"…), por isso reconhecem-se as várias formas de escrever cada canal, sem confundir com outros parecidos (a RTP 1 não é a RTP Açores nem a RTP Internacional).':
      'Names vary a lot from list to list ("RTP 1", "PT: RTP1 HD", "RTP-1"…), so the different ways of writing each channel are recognised, without mixing them up with similar ones (RTP 1 is not RTP Açores nor RTP Internacional).',
  'Preferem-se as versões portuguesas e, de cada canal, testam-se no máximo três variantes.':
      'Portuguese versions are preferred and, for each channel, at most three variants are tested.',
  'Se um canal de teste não existe na lista, isso conta como prova contra ela.':
      'If a test channel does not exist in the list, that counts as proof against it.',
  '4. Ver se chega imagem':
      '4. Checking that a picture arrives',
  'Para cada variante pede-se o endereço do vídeo e lê-se o início do que o servidor envia.':
      'For each variant the video address is requested and the start of what the server sends is read.',
  'Só conta como imagem se o que chega for mesmo vídeo: uma página de erro, uma mensagem ou uma resposta vazia não contam.':
      'It only counts as a picture if what arrives is really video: an error page, a message or an empty reply do not count.',
  'Se a primeira leitura falhar, espera-se uns segundos e tenta-se uma segunda vez (há servidores que só respondem à segunda).':
      'If the first read fails, it waits a few seconds and tries a second time (some servers only answer the second time).',
  'Assim que um canal de teste dá imagem, a lista funciona. Se algum ainda estava por testar quando o tempo acabou, a lista funciona na mesma.':
      'As soon as a test channel gives a picture, the list works. If one was still to be tested when the time ran out, the list still works.',
  '5. Tempo limite':
      '5. Time limit',
  'Cada leitura de um canal tem um tempo máximo e cada lista tem um tempo máximo no total (os dois ajustam-se nas Definições).':
      'Each channel read has a maximum time and each list has a maximum total time (both are set in Settings).',
  'Se o tempo acabar sem resposta, a lista fica inconclusiva: demorar não prova que esteja morta.':
      'If the time runs out without an answer, the list is inconclusive: being slow does not prove it is dead.',
  '6. Segunda volta para as inconclusivas':
      '6. Second round for the inconclusive ones',
  'Uma lista inconclusiva é testada outra vez, com o dobro do tempo.':
      'An inconclusive list is tested again, with twice the time.',
  'Só se repete quando a resposta pode mudar. A segunda volta aproveita o que a primeira já conseguiu: não volta a pedir a lista de canais e só repete os canais de teste que ficaram em dúvida.':
      'It is only repeated when the answer can change. The second round reuses what the first one got: it does not ask for the channel list again and only repeats the test channels that were in doubt.',
  'Se o servidor recusou por excesso de ligações, espera-se um pouco antes de tentar outra vez.':
      'If the server refused because of too many connections, it waits a little before trying again.',
  'A segunda volta começa assim que o servidor dessa lista fica livre, sem esperar pelas outras listas.':
      'The second round starts as soon as that list\'s server is free, without waiting for the other lists.',
  'Se na segunda volta o tempo voltar a acabar, fica o resultado da primeira.':
      'If the time runs out again in the second round, the result of the first one stays.',
  'Respeito pelos servidores':
      'Respect for the servers',
  'Verificam-se várias listas ao mesmo tempo (quantas, escolhe-se nas Definições), mas com cuidado para não sobrecarregar ninguém:':
      'Several lists are checked at the same time (how many is chosen in Settings), but carefully, so as not to overload anyone:',
  '• cada servidor recebe um pedido de cada vez, com um pequeno intervalo entre pedidos;':
      '• each server gets one request at a time, with a short pause between requests;',
  '• o mesmo endereço MAC nunca é usado por duas verificações ao mesmo tempo;':
      '• the same MAC address is never used by two checks at the same time;',
  '• dá-se preferência a listas de servidores que não estejam já a ser testados;':
      '• lists from servers that are not already being tested are preferred;',
  '• se um servidor pedir para abrandar, a verificação espera.':
      '• if a server asks to slow down, the check waits.',
  'As listas que já eram inconclusivas na verificação anterior vão à frente e começam logo com o dobro do tempo, porque costumam ser as mais lentas.':
      'Lists that were already inconclusive in the previous check go first and start straight away with twice the time, because they tend to be the slowest.',
  'Parar e o relatório':
      'Stopping and the report',
  'Pode sair do ecrã: a verificação continua sozinha.':
      'You can leave the screen: the check carries on by itself.',
  'Ao parar, as listas que já chegaram ao fim ficam com o resultado guardado e aparecem no relatório. As que estavam na fila ou a meio ficam como estavam.':
      'When stopping, the lists that already finished keep their saved result and appear in the report. The ones that were queued or halfway stay as they were.',
  'Como é feita a verificação':
      'How the check works',
  'Verificar':
      'Check',
  'Exportar':
      'Export',
  'Enviar':
      'Send',
  'Selecione as listas a verificar.':
      'Select the lists to check.',
  'A lista selecionada já está na fila.':
      'The selected list is already queued.',
  'As listas selecionadas já estão na fila.':
      'The selected lists are already queued.',
  '1 lista entrou na fila.':
      '1 list was queued.',
  '{0} listas entraram na fila.':
      '{0} lists were queued.',
  'Importe listas primeiro.':
      'Import lists first.',
  'Todas as listas já estão na fila.':
      'All lists are already queued.',
  'Verificação parada. O relatório fica no ecrã da verificação.':
      'Check stopped. The report stays on the check screen.',
  'A lista marcada ainda está a ser verificada.':
      'The ticked list is still being checked.',
  'As listas marcadas ainda estão a ser verificadas.':
      'The ticked lists are still being checked.',
  'Já não há listas para enviar.':
      'There are no more lists to send.',
  'Enviar {0} para Ver TV':
      'Send {0} to Watch TV',
  'Não foi possível enviar ({0}). As listas de Ver TV não mudaram.':
      'Could not send ({0}). The Watch TV lists did not change.',
  'Ir para Ver TV':
      'Go to Watch TV',
  'Marque as listas a exportar.':
      'Tick the lists to export.',
  '{0} listas exportadas.':
      '{0} lists exported.',
  'Nenhuma das listas marcadas é Stalker (portal + MAC).':
      'None of the ticked lists is Stalker (portal + MAC).',
  'Listas exportadas.{0}':
      'Lists exported.{0}',
  '{0} Guardado em {1}':
      '{0} Saved to {1}',
  'Selecione as listas a remover.':
      'Select the lists to remove.',
  'Está a ser verificada: a verificação é cancelada. ':
      'It is being checked: the check is cancelled. ',
  'Uma delas está a ser verificada: essa verificação é cancelada. ':
      'One of them is being checked: that check is cancelled. ',
  '{0} delas estão a ser verificadas: essas verificações são canceladas. ':
      '{0} of them are being checked: those checks are cancelled. ',
  'Remover do Gestor?':
      'Remove from the Manager?',
  '{0} do Gestor. {1}As listas de Ver TV não mudam.':
      '{0} the Manager. {1}The Watch TV lists do not change.',
  'Remover':
      'Remove',
  'resumo do Gestor':
      'Manager summary',
  'mudar de passo na faixa':
      'change step on the strip',
  'ações':
      'actions',
  'Gestor de listas':
      'List manager',
  'Importar listas':
      'Import lists',
  'Verificar listas':
      'Check lists',
  'Exportar listas':
      'Export lists',
  'Passos do Gestor':
      'Manager steps',
  'Última importação':
      'Last import',
  'Entraram':
      'Added',
  'Importe listas primeiro':
      'Import lists first',
  'por verificar':
      'not checked',
  'Em Ver TV':
      'In Watch TV',
  'Última exportação':
      'Last export',
  '{0} no Gestor · escolhe por onde começar':
      '{0} in the Manager · choose where to start',
  'Não foi possível abrir os ficheiros: {0}':
      'Could not open the files: {0}',
  'Importar ficheiros':
      'Import files',
  'Cole primeiro as listas, uma por linha.':
      'Paste the lists first, one per line.',
  'Importar texto colado':
      'Import pasted text',
  'Adicionar lista · {0}':
      'Add list · {0}',
  'a procurar os posts':
      'searching the posts',
  'Pesquisa parada. Nenhuma lista foi junta ao Gestor.':
      'Search stopped. No list was added to the Manager.',
  'Não foi possível pesquisar: {0}':
      'Could not search: {0}',
  'Ainda não há listas em Ver TV.':
      'There are no lists in Watch TV yet.',
  'Importar de Ver TV':
      'Import from Watch TV',
  'As listas novas já estão na fila.':
      'The new lists are already queued.',
  'O Gestor já está vazio.':
      'The Manager is already empty.',
  'Limpar o Gestor?':
      'Clear the Manager?',
  '{0}. As listas de Ver TV não mudam.':
      '{0}. The Watch TV lists do not change.',
  'Limpar':
      'Clear',
  'Ficheiros':
      'Files',
  'Accounts.json, .ini, .m3u, .txt':
      'Accounts.json, .ini, .m3u, .txt',
  'Adicionar lista':
      'Add list',
  'Portal MAC, Xtream ou M3U':
      'MAC portal, Xtream or M3U',
  'Publicadas entre duas datas':
      'Published between two dates',
  'De Ver TV':
      'From Watch TV',
  'Ainda não há listas em Ver TV':
      'There are no lists in Watch TV yet',
  'As {0} listas que já tens':
      'The {0} lists you already have',
  'Escolha um ou mais ficheiros: Accounts.json, .ini, .m3u ou .txt.':
      'Choose one or more files: Accounts.json, .ini, .m3u or .txt.',
  'Escolher ficheiros':
      'Choose files',
  'Nova lista':
      'New list',
  'Escolha o tipo de lista e preencha os dados.':
      'Choose the list type and fill in the details.',
  'Juntar ao Gestor':
      'Add to the Manager',
  'Junta as listas publicadas no blog entre duas datas, sem duplicar.':
      'Adds the lists published on the blog between two dates, without duplicates.',
  'Escolher datas · {0} – {1}':
      'Choose dates · {0} – {1}',
  'Copia {0} de Ver TV para o Gestor, sem duplicar.':
      'Copies {0} from Watch TV to the Manager, without duplicates.',
  'Endereço do portal':
      'Portal address',
  'Endereço MAC':
      'MAC address',
  'Link Xtream':
      'Xtream link',
  'Servidor':
      'Server',
  'Utilizador':
      'Username',
  'Palavra-passe':
      'Password',
  'Endereço da lista':
      'List address',
  'Cole as listas, uma por linha (portal e MAC, ligação Xtream ou M3U).':
      'Paste the lists, one per line (portal and MAC, Xtream or M3U link).',
  'Com erro ({0})':
      'With error ({0})',
  'Cancelada.':
      'Cancelled.',
  'Encontradas':
      'Found',
  'Novas no Gestor':
      'New in the Manager',
  'Já estavam no Gestor':
      'Already in the Manager',
  'Verificar a 1 nova':
      'Check the 1 new one',
  'Verificar as {0} novas':
      'Check the {0} new ones',
  'Resultado':
      'Result',
  'Limpar o Gestor':
      'Clear the Manager',
  'faltam cerca de {0} s':
      'about {0} s left',
  'faltam cerca de {0} min':
      'about {0} min left',
  'A testar canal {0} de {1}':
      'Testing channel {0} of {1}',
  '{0} de {1} canais com imagem':
      '{0} of {1} channels with picture',
  'Verificação parada: {0}':
      'Check stopped: {0}',
  'Última verificação: {0}':
      'Last check: {0}',
  'Verificação parada: nenhuma lista chegou ao fim':
      'Check stopped: no list finished',
  'Pode sair, continua sozinha':
      'You can leave, it carries on by itself',
  'Verificar mais (fila)':
      'Check more (queue)',
  'Verificar todas ({0})':
      'Check all ({0})',
  'não funciona':
      'does not work',
  'não funcionam':
      'do not work',
  'Canais de teste: {0}':
      'Test channels: {0}',
  'Alterar nas Definições':
      'Change in Settings',
  '{0} por verificar':
      '{0} not checked',
  'Progresso da verificação: {0} de {1}':
      'Check progress: {0} of {1}',
  'Pede a lista de canais outra vez ao servidor':
      'Asks the server for the channel list again',
  'Verificar agora':
      'Check now',
  'Testa 3 canais · cerca de 20 s':
      'Tests 3 channels · about 20 s',
  'Editar lista':
      'Edit list',
  'Nome, endereço, MAC ou utilizador':
      'Name, address, MAC or username',
  'Pôr nas favoritas':
      'Add to favourites',
  'Fica à mão no filtro «Favoritas»':
      'Kept at hand in the «Favourites» filter',
  'Copiar link':
      'Copy link',
  'Só no Windows · leva os dados de acesso':
      'Windows only · carries the access details',
  'Enviar para o Gestor':
      'Send to the Manager',
  'Para verificar ou exportar com as outras':
      'To check or export with the others',
  'Remover lista':
      'Remove list',
  'Pede confirmação · os favoritos desta lista saem':
      'Asks for confirmation · this list\'s favourites are removed',
  'Tirar das favoritas':
      'Remove from favourites',
  'Deixa de aparecer no filtro «Favoritas»':
      'No longer appears in the «Favourites» filter',
  'Indique o endereço':
      'Enter the address',
  'O endereço tem de começar por http:// ou https://':
      'The address must start with http:// or https://',
  'MAC inválido (ex.: 00:1A:79:00:00:01)':
      'Invalid MAC (e.g. 00:1A:79:00:00:01)',
  'Indique o utilizador (ou apague a password)':
      'Enter the username (or delete the password)',
  'Indique a password (ou apague o utilizador)':
      'Enter the password (or delete the username)',
  'Remover lista?':
      'Remove list?',
  'A lista {0} sai de Ver TV (os favoritos e a cache de canais também).':
      'The list {0} leaves Watch TV (its favourites and channel cache too).',
  'Lista guardada.':
      'List saved.',
  'Lista guardada. Os canais vão ser pedidos de novo ao abrir.':
      'List saved. The channels will be requested again when it opens.',
  'Não foi guardada: {0}.':
      'Not saved: {0}.',
  'Não foi possível guardar a lista.':
      'Could not save the list.',
  'Nome (opcional)':
      'Name (optional)',
  'Endereço':
      'Address',
  'Utilizador (Xtream)':
      'Username (Xtream)',
  'Password (Xtream)':
      'Password (Xtream)',
  'Com MAC é Stalker; com utilizador e password é Xtream; só o endereço é M3U.':
      'With a MAC it is Stalker; with username and password it is Xtream; just the address is M3U.',
  'Guardar':
      'Save',
  'Ordenar as listas':
      'Sort the lists',
  'As favoritas ficam sempre à frente.':
      'Favourites always stay in front.',
  'Canal {0}':
      'Channel {0}',
  'Continuar a ver {0}, {1}':
      'Continue watching {0}, {1}',
  'Ver':
      'Watch',
  'Continuar a ver':
      'Continue watching',
  'Favorita':
      'Favourite',
  'Opções da lista':
      'List options',
  'verificada agora':
      'checked just now',
  'verificada há {0} min':
      'checked {0} min ago',
  'verificada há {0} h':
      'checked {0} h ago',
  'verificada há {0} {1}':
      'checked {0} {1} ago',
  'verificada em {0}/{1}/{2}':
      'checked on {0}/{1}/{2}',
  'Favoritas':
      'Favourites',
  'Link copiado':
      'Link copied',
  'Enviada para o Gestor':
      'Sent to the Manager',
  'Já estava no Gestor':
      'Already in the Manager',
  'A atualizar os canais de {0}…':
      'Updating the channels of {0}…',
  'Canais de {0} atualizados · {1}':
      'Channels of {0} updated · {1}',
  'Não foi possível atualizar {0}: {1}':
      'Could not update {0}: {1}',
  'Novidades da versão {0}':
      'What\'s new in version {0}',
  'Ver todas':
      'See all',
  'Versão {0}':
      'Version {0}',
  'Posição':
      'Position',
  'Esquerda e direita: {0} s para trás ou para a frente':
      'Left and right: {0} s back or forward',
  'Abrir em modo compatível':
      'Open in compatible mode',
  'Canal visto antes':
      'Previously watched channel',
  'Voltar à lista':
      'Back to the list',
  'Direta (recomendada)':
      'Direct (recommended)',
  'Compatível':
      'Compatible',
  'O aparelho perde imagens com o desentrelaçamento por campo: volta a descodificação Direta':
      'The device drops frames with per-field deinterlacing: back to Direct decoding',
  'Modo compatível ativado para desentrelaçar este canal':
      'Compatible mode turned on to deinterlace this channel',
  'Ligar o som':
      'Unmute',
  'Silêncio':
      'Mute',
  '{0} · em direto':
      '{0} · live',
  '{0} › {1} · em direto':
      '{0} › {1} · live',
  'Velocidade':
      'Speed',
  'Voltar ao direto':
      'Back to live',
  'Canal anterior':
      'Previous channel',
  'Recuar 10 s':
      'Back 10 s',
  'Pausa':
      'Pause',
  'Reproduzir':
      'Play',
  'Avançar 10 s':
      'Forward 10 s',
  'Canal seguinte':
      'Next channel',
  'Ecrã inteiro (F11)':
      'Full screen (F11)',
  'Em direto':
      'Live',
  'Limpa as linhas dos canais entrelaçados (1080i/576i/480i). Por campo, quando o aparelho o permite: até 50 imagens/s (60 nos 480i); senão às imagens/s do canal.':
      'Cleans the lines of interlaced channels (1080i/576i/480i). Per field, when the device allows it: up to 50 frames/s (60 for 480i); otherwise at the channel\'s frames/s.',
  'ligado (bwdif, por campo)':
      'on (bwdif, per field)',
  'ligado (d3d11vpp, por campo)':
      'on (d3d11vpp, per field)',
  'ligado (shader do player)':
      'on (player shader)',
  'à espera da imagem':
      'waiting for the picture',
  'desligado (imagem progressiva)':
      'off (progressive picture)',
  'indisponível neste aparelho':
      'not available on this device',
  'descodificação (imagens perdidas no descodificador)':
      'decoding (frames dropped in the decoder)',
  'ecrã (imagens perdidas na saída / 50 fps num ecrã a 60 Hz)':
      'screen (frames dropped at the output / 50 fps on a 60 Hz screen)',
  'Descodificação':
      'Decoding',
  'Resolução':
      'Resolution',
  'Imagens/s (canal · medido)':
      'Frames/s (channel · measured)',
  'Ecrã (Hz)':
      'Screen (Hz)',
  'Perdidas (saída · descodificador)':
      'Dropped (output · decoder)',
  'Estado do buffer':
      'Buffer status',
  'Débito do vídeo':
      'Video bitrate',
  'À espera da rede':
      'Waiting for the network',
  'não':
      'no',
  ' (em túnel as perdidas não são contadas)':
      ' (in tunnel mode dropped frames are not counted)',
  'Descodificador':
      'Decoder',
  'Imagens/s':
      'Frames/s',
  'Imagens (perdidas · mostradas)':
      'Frames (dropped · shown)',
  'pedido, mas não ficou ativo':
      'requested, but did not become active',
  ' (só a interface por cima do vídeo)':
      ' (only the interface over the video)',
  'Imagens desenhadas/s (interface)':
      'Frames drawn/s (interface)',
  'Tempo de desenho':
      'Draw time',
  'Estatísticas':
      'Statistics',
  'Veredicto: {0}':
      'Verdict: {0}',
  'Português':
      'Portuguese',
  'Inglês':
      'English',
  'Espanhol':
      'Spanish',
  'Francês':
      'French',
  'Alemão':
      'German',
  'Italiano':
      'Italian',
  'Faixa {0}':
      'Track {0}',
  'Automática':
      'Automatic',
  'Desligadas':
      'Off',
  'o ExoPlayer não está disponível neste aparelho':
      'ExoPlayer is not available on this device',
  'o ExoPlayer recusou o pedido':
      'ExoPlayer refused the request',
  'o player foi aberto noutro ecrã':
      'the player was opened on another screen',
  'o ExoPlayer não conseguiu tocar o canal':
      'ExoPlayer could not play the channel',
  'Ajustes rápidos':
      'Quick settings',
  'Áudio e legendas: só este canal · o resto vale para todos':
      'Audio and subtitles: this channel only · the rest applies to all',
  'o canal não abriu':
      'the channel did not open',
  'o canal não abriu ({0})':
      'the channel did not open ({0})',
  'Este canal abriu com o motor mpv':
      'This channel opened with the mpv engine',
  'Não há mais para recuar':
      'Nothing more to rewind',
  'Já está em direto':
      'Already live',
  'Já está no fim do buffer':
      'Already at the end of the buffer',
  'nada pedido (já certo ou nenhum modo serve)':
      'nothing requested (already right or no mode fits)',
  'sem salto':
      'no jump',
  'Modo compatível ativado para este canal':
      'Compatible mode turned on for this channel',
  'Não há o canal {0} nesta lista':
      'There is no channel {0} in this list',
  'desligado (imagem reduzida no ecrã)':
      'off (picture reduced on screen)',
  'Este aparelho não permite o desentrelaçamento do player':
      'This device does not allow the player\'s deinterlacing',
  'Em todas as imagens, também nas que parecem progressivas':
      'On every frame, including those that look progressive',
  'Só nas imagens entrelaçadas (1080i/576i/480i)':
      'Only on interlaced frames (1080i/576i/480i)',
  'Por campo (50 imagens/s; 60 nos 480i); na descodificação Direta um direto entrelaçado reabre em Compatível':
      'Per field (50 frames/s; 60 for 480i); with Direct decoding an interlaced live channel reopens in Compatible',
  'Por campo (50 imagens/s; 60 nos 480i), {0}':
      'Per field (50 frames/s; 60 for 480i), {0}',
  'Em todas as imagens; limpa as linhas sem dobrar as imagens/s':
      'On every frame; cleans the lines without doubling the frames/s',
  'Só nas imagens entrelaçadas (1080i/576i/480i); limpa as linhas sem dobrar as imagens/s':
      'Only on interlaced frames (1080i/576i/480i); cleans the lines without doubling the frames/s',
  'Formato de imagem':
      'Picture format',
  'Qualidade / faixa de vídeo':
      'Quality / video track',
  'Este canal só tem uma':
      'This channel only has one',
  'Faixa de áudio':
      'Audio track',
  'Legendas':
      'Subtitles',
  'Este canal não tem legendas':
      'This channel has no subtitles',
  'Atraso do áudio':
      'Audio delay',
  'Positivo: o som chega mais tarde':
      'Positive: the sound arrives later',
  'Software (sem hardware)':
      'Software (no hardware)',
  'Este canal está em {0} (sem imagem na direta, ou entrelaçado)':
      'This channel is in {0} (no picture in Direct, or interlaced)',
  'Compatível: para imagem preta ou cores erradas':
      'Compatible: for a black picture or wrong colours',
  'Desligue se a imagem aparecer com defeitos':
      'Turn off if the picture shows defects',
  '50 Hz nos canais a 50 imagens/s (sem saltos)':
      '50 Hz on channels at 50 frames/s (no stutter)',
  'Informação do stream':
      'Stream information',
  'Esconder':
      'Hide',
  'Mostrar':
      'Show',
  'Resolução, codec, débito e buffer':
      'Resolution, codec, bitrate and buffer',
  'Modo de descodificação':
      'Decoding mode',
  'Saída · hwdec pedido':
      'Output · hwdec requested',
  'Motor':
      'Engine',
  'Linhas no ecrã · do vídeo':
      'Lines on screen · of the video',
  'Taxa do ecrã pedida':
      'Requested screen rate',
  'o canal não começou a tempo (sem imagem em {0} s)':
      'the channel did not start in time (no picture in {0} s)',
  'Ver TV':
      'Watch TV',
  'Gestor':
      'Manager',
  'Verificação parada. Nenhuma lista chegou ao fim.':
      'Check stopped. No list finished.',
  'Ver resultados':
      'See results',
  'Carregue outra vez em Voltar para sair':
      'Press Back again to exit',
  'hoje às {0}':
      'today at {0}',
  'ontem às {0}':
      'yesterday at {0}',
  'até {0}/{1}/{2}':
      'until {0}/{1}/{2}',
  'as favoritas':
      'favourites',
  'as que funcionam':
      'working ones',
  'as inconclusivas':
      'inconclusive ones',
  'Ver TV fica só com estas.':
      'Watch TV keeps only these.',
  'Ver TV fica com estas e com {0}.':
      'Watch TV keeps these and {0}.',
  'As que funcionam':
      'Working ones',
  'As inconclusivas':
      'Inconclusive ones',
  'Adicionar às listas de Ver TV':
      'Add to the Watch TV lists',
  'As que já lá estão ficam. Repetidas não se duplicam.':
      'The ones already there stay. Repeated ones are not duplicated.',
  'Substituir as listas de Ver TV':
      'Replace the Watch TV lists',
  'Das listas que já estão em Ver TV, manter:':
      'Of the lists already in Watch TV, keep:',
  'Para o sfvip player':
      'For sfvip player',
  'Ficheiros .ini num zip':
      '.ini files in a zip',
  'Para o Stalker Portal Player':
      'For Stalker Portal Player',
  'O ficheiro leva os dados de acesso das listas. Guarda-o num sítio seguro.':
      'The file carries the lists\' access details. Keep it somewhere safe.',
  'Escolher onde guardar':
      'Choose where to save',
  'Parar a verificação?':
      'Stop the check?',
  'As listas que já foram verificadas ficam com o resultado guardado e o relatório mostra-as. As que estão na fila ou a meio ficam como estavam.':
      'Lists already checked keep their saved result and the report shows them. The ones queued or halfway stay as they were.',
  'credenciais ou acesso recusados (401)':
      'credentials or access refused (401)',
  'acesso proibido (403)':
      'access forbidden (403)',
  'servidor a limitar pedidos (429)':
      'server limiting requests (429)',
  'o painel recusa todos os canais (456) — MAC em uso noutro aparelho?':
      'the panel refuses all channels (456) — MAC in use on another device?',
  'servidor recusou temporariamente (458)':
      'server refused temporarily (458)',
  'limite de ligações simultâneas atingido (459)':
      'simultaneous connection limit reached (459)',
  'servidor recusou temporariamente (461)':
      'server refused temporarily (461)',
  'tempo esgotado':
      'timed out',
  'resposta grande demais (mais de {0} MB)':
      'reply too large (more than {0} MB)',
  'ligação falhou ({0})':
      'connection failed ({0})',
  'ligação cortada pelo servidor':
      'connection cut by the server',
  'na fila':
      'queued',
  'inconclusiva: à espera da 2.ª volta':
      'inconclusive: waiting for the 2nd round',
  'a começar':
      'starting',
  'inconclusiva: a testar outra vez':
      'inconclusive: testing again',
  'sem rede (o DNS não confirmou o endereço)':
      'no network (DNS did not confirm the address)',
  'DNS sem resposta':
      'DNS no reply',
  'DNS: {0} não existe':
      'DNS: {0} does not exist',
  'tempo esgotado (limite de {0}s por {1})':
      'timed out (limit of {0}s per {1})',
  'a usar os canais lidos na 1.ª volta':
      'using the channels read in the 1st round',
  'não foi possível listar os canais (a API respondeu {0})':
      'could not list the channels (the API replied {0})',
  'lista vazia ou inválida':
      'empty or invalid list',
  'conta sem canais':
      'account without channels',
  '{0} não encontrada (lista de canais incompleta)':
      '{0} not found (incomplete channel list)',
  '{0} não existe na {1}':
      '{0} does not exist in the {1}',
  'limite de ligações atingido ({0}) — {1}':
      'connection limit reached ({0}) — {1}',
  'o link do canal falhou: {0}':
      'the channel link failed: {0}',
  'playlist sem entradas':
      'playlist without entries',
  'playlist HLS com demasiados níveis':
      'HLS playlist with too many levels',
  'stream recusado apesar de conta ativa ({0}) — possível limite de ligações':
      'stream refused despite an active account ({0}) — possible connection limit',
  'resposta vazia ou curta demais':
      'empty or too short reply',
  'resposta não é vídeo':
      'reply is not video',
  'vídeo recebido':
      'video received',
  'Favoritos · {0}':
      'Favourites · {0}',
  'Pesquisar listas':
      'Search lists',
  'Ordenar: {0}':
      'Sort: {0}',
  'Listas · {0}':
      'Lists · {0}',
  'Nenhuma lista com este filtro.':
      'No list with this filter.',
  'Ainda não há listas para ver':
      'No lists to watch yet',
  'As listas entram pelo Gestor. Lá podes importá-las, ver quais funcionam e enviar as boas para aqui.':
      'Lists come in through the Manager. There you can import them, see which ones work and send the good ones here.',
  'Importar':
      'Import',
  'Testamos 3 canais de cada lista':
      'We test 3 channels of each list',
  'As que funcionam aparecem aqui':
      'The working ones appear here',
  'Ir para o Gestor':
      'Go to the Manager',
  'opções da lista':
      'list options',
  'de Ver TV':
      'Watch TV',
  'do Gestor':
      'Manager',
  'em {0}':
      'on {0}',
  'entre {0} e {1}':
      'between {0} and {1}',
  'a descarregar a lista':
      'downloading the list',
  'sem resposta':
      'no reply',
  'conta {0}':
      'account {0}',
  'Não foi encontrada nenhuma lista no texto.':
      'No list was found in the text.',
  '1 canal':
      '1 channel',
  '{0} canais':
      '{0} channels',
  'da lista':
      'as in list',
  'em ':
      'on ',
  '{0} de {1}':
      '{0} of {1}',
  ', mais as definições':
      ', plus the settings',
  ' Na descodificação Direta, um direto entrelaçado reabre em Compatível.':
      ' With Direct decoding, an interlaced live channel reopens in Compatible.',
  ' OK para mudar um valor, depois ← →; ↑ ↓ mudam de opção.':
      ' OK to change a value, then ← →; ↑ ↓ move between options.',
  'A verificar {0}/{1}':
      'Checking {0}/{1}',
  '1 lista':
      '1 list',
  '{0} listas':
      '{0} lists',
  ' {0} sem MAC (Xtream/M3U) ficaram de fora.':
      ' {0} without MAC (Xtream/M3U) were left out.',
  'A lista selecionada sai':
      'The selected list leaves',
  'As {0} listas selecionadas saem':
      'The {0} selected lists leave',
  'ontem':
      'yesterday',
  'OK: abrir →':
      'OK: open →',
  'passo 2 · Verificar':
      'step 2 · Check',
  'LISTA':
      'LIST',
  'ESTADO':
      'STATUS',
  'MOTIVO':
      'REASON',
  'TESTE':
      'TEST',
  'A lista do Gestor sai':
      'The Manager list leaves',
  'As {0} listas do Gestor saem':
      'The {0} Manager lists leave',
  'a lista':
      'the list',
  'as {0} listas':
      'the {0} lists',
  'A verificar {0}':
      'Checking {0}',
  'parou':
      'stopped',
  'terminou':
      'finished',
  '{0} de {1} verificadas':
      '{0} of {1} checked',
  'CONTINUAR A VER · lista {0}':
      'CONTINUE WATCHING · list {0}',
  '{0} canais · {1} grupos':
      '{0} channels · {1} groups',
  'dia':
      'day',
  'dias':
      'days',
  'A verificar {0}…':
      'Checking {0}…',
  'ligado (bwdif, a medir)':
      'on (bwdif, measuring)',
  'ligado (d3d11vpp, a medir)':
      'on (d3d11vpp, measuring)',
  'desligado':
      'off',
  'sim':
      'yes',
  'ativo':
      'active',
  'a medir…':
      'measuring…',
  'em todas as imagens':
      'on every frame',
  'só nas imagens entrelaçadas':
      'only on interlaced frames',
  'lista':
      'list',
  'listas':
      'lists',
  'lista verificada':
      'list checked',
  'listas verificadas':
      'lists checked',
  'nova':
      'new',
  'novas':
      'new',
  'atualizada':
      'updated',
  'atualizadas':
      'updated',
  'removida':
      'removed',
  'removidas':
      'removed',
  '1 lista enviada para Ver TV':
      '1 list sent to Watch TV',
  '{0} listas enviadas para Ver TV':
      '{0} lists sent to Watch TV',
  'já lá estavam iguais':
      'they were already there, unchanged',
  ' · {0} ainda a verificar':
      ' · {0} still being checked',
  'A verificar · {0}':
      'Checking · {0}',
  '★ Favoritos':
      '★ Favourites',
  'Favoritos':
      'Favourites',
  'Canais':
      'Channels',
  'OK mantido':
      'OK held',
  'pesquisa':
      'search',
  'abrir':
      'open',
  'limpar':
      'clear',
  'ver':
      'watch',
  'favorito':
      'favourite',
  'grupos':
      'groups',
  'ir para o canal':
      'go to channel',
  'opções dos canais':
      'channel options',
  'marcar':
      'mark',
  'abrir o passo':
      'open the step',
  'escolher':
      'choose',
  'a ligar ao portal':
      'connecting to the portal',
  'Idioma · Language':
      'Language',
  'Idioma da aplicação':
      'App language',
  'Os textos de todos os ecrãs mudam logo.':
      'The text on every screen changes right away.',
  '{0} (sistema)':
      '{0} (system)',
  'Menos':
      'Less',
  'Mais':
      'More',
  'Parada':
      'Stopped',
  'Sem grupo':
      'No group',
  'Definições › Idioma · Language: a app pode ficar em inglês (English). Muda logo, sem reiniciar.':
      'Settings › Language: the app can be in English. It changes right away, without restarting.',
  'Ao ver um canal: ao carregar em OK na barra do volume, ela dá um pulo e mostra as setas ‹ › enquanto se ajusta.':
      'While watching a channel: pressing OK on the volume bar makes it pulse and shows the ‹ › arrows while you adjust it.',
  'Ficheiros, texto ou de Ver TV':
      'Files, text or from Watch TV',
  'Ficheiro ou texto colado':
      'File or pasted text',
  '{0} encontradas':
      '{0} found',
  'a procurar':
      'searching',
  '1 tarefa a decorrer':
      '1 task running',
  '{0} tarefas a decorrer':
      '{0} tasks running',
  '{0} a decorrer · {1} terminadas':
      '{0} running · {1} finished',
  'abriu {0}':
      'opened {0}',
  'A importar…':
      'Importing…',
  'A importar · {0}':
      'Importing · {0}',
  'a API respondeu {0}':
      'the API replied {0}',
  'A ligar…':
      'Connecting…',
  'Em inglês: o progresso da verificação («Testing channel 2 of 3») e o das páginas ao carregar um portal voltam a aparecer, e as últimas frases que ficavam em português foram traduzidas.':
      'In English: the check progress ("Testing channel 2 of 3") and the page progress when loading a portal show again, and the last sentences still in Portuguese were translated.',
  'No telemóvel: as barras do volume e o deslize na lateral do ecrã mudam o volume do sistema e acompanham as teclas do telefone. Saiu a opção «Volume inicial do sistema».':
      'On phones: the volume bars and the swipe on the side of the screen change the system volume and follow the phone\'s keys. The "Initial system volume" option was removed.',
  'Novidades: cada versão mostra a data em que saiu.':
      'What\'s new: each version shows the date it was released.',
  'No telemóvel: o motor do player passa a ser o mpv por omissão.':
      'On phones: the player engine is now mpv by default.',
  'No telemóvel: ao exportar (Accounts.json ou a cópia de segurança) escolhe-se a pasta onde gravar.':
      'On phones: when exporting (Accounts.json or the backup) you choose the folder to save to.',
  'Ao desinstalar, a app já não deixa as listas nem o «Continuar a ver» numa cópia de segurança do Android.':
      'When uninstalled, the app no longer leaves the lists or "Continue watching" in an Android backup.',
  // o guia (EPG) em Ver TV
  'falta 1 min':
      '1 min left',
  'faltam {0} min':
      '{0} min left',
  'falta {0} h {1}':
      '{0} h {1} left',
  'Canal {0} · {1}':
      'Channel {0} · {1}',
  'Nos favoritos':
      'In favourites',
  'Esta lista não tem programação.':
      'This list has no TV guide.',
  'A carregar a programação…':
      'Loading the TV guide…',
  'Sem programação disponível.':
      'No TV guide available.',
  'AGORA':
      'NOW',
  'A SEGUIR':
      'NEXT',
  'A carregar a programação: a pesquisa pelo programa ainda não está completa.':
      'Loading the TV guide: searching by programme is not complete yet.',
  'Esta lista não tem a programação de todos os canais: a pesquisa é só pelo nome.':
      'This list has no TV guide for all channels: search is by name only.',
  '{0} pelo programa':
      '{0} by programme',
  'A dar: {0}':
      'On now: {0}',
  'A seguir: {0}':
      'Next: {0}',
  'Agora: {0}':
      'Now: {0}',
  'A programação de todos os canais ficou por descarregar (dados móveis): a pesquisa é só pelo nome.':
      'The TV guide for all channels was not downloaded (mobile data): search is by name only.',
  'Ver TV: programação (EPG) nas listas Xtream e nos portais MAC. Na TV e no computador, uma coluna à direita mostra o canal com o foco, o programa a dar (com o progresso e a descrição) e os seguintes.':
      'Watch TV: TV guide (EPG) for Xtream lists and MAC portals. On TV and computer, a column on the right shows the focused channel, the programme on now (with progress and description) and the next ones.',
  'Ver TV: a pesquisa também encontra os canais pelo programa a dar ou pelo seguinte.':
      'Watch TV: search also finds channels by the programme on now or the next one.',
  'No telemóvel: «Agora: …» por baixo de cada canal; o toque longo abre os detalhes, com «Ver» e os favoritos.':
      'On phones: "Now: …" under each channel; a long press opens the details, with "Watch" and favourites.',
  'No telemóvel: Definições › Ligação › «Poupar dados móveis». Com dados móveis, a app pergunta antes de descarregar a programação, carregar canais ou verificar listas.':
      'On phones: Settings › Connection › "Save mobile data". On mobile data, the app asks before downloading the TV guide, loading channels or checking lists.',
  // poupar dados móveis
  'Poupar dados móveis':
      'Save mobile data',
  'Com dados móveis ou numa rede limitada, pergunta antes de descarregar a programação de todos os canais, carregar os canais de uma lista ou verificar listas.':
      'On mobile data or a metered network, asks before downloading the TV guide for all channels, loading a list\'s channels or checking lists.',
  'Está a usar dados móveis':
      'You are on mobile data',
  'Está numa rede limitada':
      'You are on a metered network',
  'Descarregar a programação de todos os canais desta lista? Pode gastar dezenas de MB. Sem ela, a programação de um canal só é pedida quando o escolhe (poucos dados), e a pesquisa é só pelo nome.':
      'Download the TV guide for all channels in this list? It can use tens of MB. Without it, a channel\'s guide is only fetched when you pick it (little data), and search is by name only.',
  'Descarregar':
      'Download',
  'Carregar os canais desta lista do servidor? Uma lista grande pode gastar vários MB.':
      'Load this list\'s channels from the server? A large list can use several MB.',
  'Carregar':
      'Load',
  'Verificar a lista? Descarrega os canais dela e testa alguns: pode gastar vários MB.':
      'Check the list? It downloads its channels and tests some: it can use several MB.',
  'Verificar {0} listas? Cada uma descarrega os canais e testa alguns: pode gastar muitos MB.':
      'Check {0} lists? Each one downloads its channels and tests some: it can use many MB.',
  'Pode desligar este aviso em Definições › Ligação › Poupar dados móveis.':
      'You can turn this off in Settings › Connection › Save mobile data.',
  'Agora não':
      'Not now',
  'carregamento adiado para poupar dados móveis':
      'loading postponed to save mobile data',
  // o stbstalker não existe na edição de partilha (nem as traduções dele)
  'Ver TV: «A seguir» já não repete um programa que está dentro do que está a dar.':
      'Watch TV: "Next" no longer repeats a programme that sits inside the one on now.',
  'Os sites com certificados da nova raiz da GoDaddy (de 2025) já não dão «falha na ligação segura» no Windows nem em aparelhos Android antigos.':
      'Sites with certificates from the new GoDaddy root (2025) no longer give "secure connection failed" on Windows or older Android devices.',
  'Novo visual: azul profundo, cartões e painéis escuros e azul elétrico, com um fundo de faixas de luz.':
      'New look: deep blue, dark cards and panels and electric blue, with a background of light bands.',
  'O foco do comando tem agora uma mira: quatro cantos que se fecham sobre o que está escolhido.':
      'Remote focus now has a viewfinder: four corners that close in on what is selected.',
  'Animações mais suaves ao mudar de ecrã e de foco (desligadas com «reduzir movimento»).':
      'Smoother animations when changing screen and focus (off with "reduce motion").',
  'Barra lateral mais estreita, só com os ícones: sobra mais espaço para as listas e os canais.':
      'Narrower sidebar with icons only: more room for lists and channels.',
  'Ver TV: o programa a dar num painel próprio, com o ponto do direto a pulsar.':
      'Watch TV: the programme on now in its own panel, with a pulsing live dot.',
  'Ver TV na TV: numa lista enorme, o cabeçalho dos canais já não sai do ecrã enquanto se ordena.':
      'Watch TV on TV: in a huge list, the channels header no longer overflows while sorting.',
  'Letra nova em toda a app: Inter no texto e Space Grotesk nos títulos e nos números grandes.':
      'New typeface across the app: Inter for text and Space Grotesk for titles and big numbers.',
  'Gestor: ao mudar de passo, o conteúdo já não salta (a barra de cima tem sempre a mesma altura).':
      'Manager: content no longer jumps when changing step (the top bar always has the same height).',
  '‹ Importar':
      '‹ Import',
  if (!edicaoPartilha) ...{
    // listas de um site
    'Gestor › Importar › Listas do Telegram: os canais ficam guardados, com favoritos (primeiro na lista) e «Todos os favoritos», que procura em todos de uma vez.':
        'Manager › Import › Telegram lists: channels are saved, with favourites (first in the list) and "All favourites", which searches them all at once.',
    'Gestor › Importar › Listas de um site: além do stbstalker, qualquer site. Nos blogs Blogger e WordPress lêem-se os posts entre as datas; noutros, a página do endereço.':
        'Manager › Import › Lists from a site: besides stbstalker, any site. On Blogger and WordPress blogs the posts between the dates are read; on others, the page at the address.',
    'A página não tem listas (Xtream, M3U ou portal MAC) no texto.':
        'The page has no lists (Xtream, M3U or MAC portal) in its text.',
    'Os posts do período não têm listas (Xtream, M3U ou portal MAC) no texto.':
        'The posts in that period have no lists (Xtream, M3U or MAC portal) in their text.',
    'Ficheiros, texto, sites, Telegram ou de Ver TV':
        'Files, text, sites, Telegram or from Watch TV',
    'Escreva o endereço do site (por exemplo https://blog.exemplo.pt).':
        'Type the site address (for example https://blog.example.com).',
    'Pesquisa em {0}':
        'Search on {0}',
    'a ler o site':
        'reading the site',
    'Não foi possível ler o site: {0}':
        'Could not read the site: {0}',
    'Listas de um site':
        'Lists from a site',
    'stbstalker, Blogger, WordPress…':
        'stbstalker, Blogger, WordPress…',
    'Junta as listas publicadas num site entre duas datas, sem duplicar. No stbstalker e nos blogs Blogger ou WordPress lêem-se os posts das datas; noutro site, ou no endereço de um post, lê-se só essa página.':
        'Adds the lists published on a site between two dates, without duplicates. On stbstalker and on Blogger or WordPress blogs the posts from those dates are read; on another site, or the address of a post, only that page is read.',
    'Endereço do site':
        'Site address',
    'Tirar dos recentes':
        'Remove from recent',
    // a gestão dos canais do Telegram
    'Escreva o nome do canal (por exemplo @nome_do_canal).':
        'Type the channel name (for example @channel_name).',
    '@{0} saiu dos canais':
        '@{0} removed from the channels',
    'Remover o canal':
        'Remove the channel',
    'Junte um canal do Telegram primeiro.':
        'Add a Telegram channel first.',
    '{0} canais favoritos':
        '{0} favourite channels',
    '@{0} ({1} de {2}) · {3} encontradas':
        '@{0} ({1} of {2}) · {3} found',
    'Todos os favoritos ({0})':
        'All favourites ({0})',
    'Ainda não há canais guardados: junte um em baixo.':
        'No saved channels yet: add one below.',
    'Os seus canais':
        'Your channels',
    'Juntar um canal':
        'Add a channel',
    'Gestor › Importar: novo «Listas do Telegram», que junta as listas publicadas num canal público (por omissão o @michelstv4) entre as datas escolhidas.':
        'Manager › Import: new "Telegram lists", which adds the lists posted on a public channel (@michelstv4 by default) between the chosen dates.',
    '‹ Importar · Listas do stbstalker':
        '‹ Import · stbstalker lists',
    'Pesquisa no stbstalker':
        'stbstalker search',
    'Ficheiros, texto, stbstalker, Telegram ou de Ver TV':
        'Files, text, stbstalker, Telegram or from Watch TV',
    'Listas do stbstalker':
        'stbstalker lists',
    'Ficheiro, texto colado, stbstalker ou Telegram':
        'File, pasted text, stbstalker or Telegram',
    // Telegram
    'Pesquisa no Telegram':
        'Telegram search',
    'Listas do Telegram':
        'Telegram lists',
    'De um canal público':
        'From a public channel',
    'Junta as listas de um canal público do Telegram, entre duas datas. Lê o texto das mensagens (Xtream, M3U e portal MAC); não lê ficheiros anexados.':
        'Adds the lists from a public Telegram channel, between two dates. It reads the message text (Xtream, M3U and MAC portal); it does not read attached files.',
    'Canal do Telegram':
        'Telegram channel',
    'Escreva o nome do canal (por exemplo @michelstv4).':
        'Enter the channel name (for example @michelstv4).',
    'a procurar as mensagens':
        'searching the messages',
    'Nenhuma mensagem publicada {0}.':
        'No message published {0}.',
  },
};
