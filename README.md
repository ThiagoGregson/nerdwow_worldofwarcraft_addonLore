# NerdWow

**Para quem joga World of Warcraft pela história.** O NerdWow transforma as conversas com NPCs em cenas de cinema e guarda num diário tudo o que o seu personagem vive: os lugares por onde passa, as missões que aceita e conclui e as conversas que tem pelo caminho.

> **Status:** em desenvolvimento (alfa). Funciona apenas no **Retail (Midnight)**. A interface e os textos do addon estão em português do Brasil.

## O que ele faz

**Conversas em modo cinema**
- Substitui a janela de conversa da Blizzard: barras de cinema, nome e brasão do NPC, e a fala aparecendo letra a letra.
- Opções numeradas, que podem ser escolhidas pelas teclas **1 a 9**.
- O visual muda conforme o lugar e o NPC: **Aliança**, **Horda**, **Quel'Thalas** ou **Neutro**.

**Missões em pergaminho**
- Oferta, progresso e conclusão aparecem num pergaminho à direita, com a legenda do NPC à esquerda.
- Papel envelhecido, selo do tema, textos completos, objetivos, itens exigidos e recompensas com tooltip nativo.
- O texto rola dentro do papel; os botões ficam sempre acessíveis no rodapé.

**Diário do personagem**
- Registra automaticamente:
  - os **locais** por onde você passa;
  - as **missões** oferecidas, aceitas e concluídas, com os textos, os objetivos e a recompensa escolhida;
  - as **conversas** com NPCs e as opções que você escolhe.
- Tudo é guardado no seu computador. Nada é enviado pela internet.

**Botão no minimapa**
- Mostra o status do diário ao passar o mouse.
- Um clique **sincroniza**, ou seja, grava o diário em disco.
- Dá para arrastar o botão para qualquer ponto da borda do minimapa.

### Em breve

- Câmera cinematográfica no NPC durante a conversa.
- Narração das falas por voz (TTS).
- Registro das falas de NPCs no chat.

## Requisitos

- World of Warcraft **Retail**, patch **12.1.5** (Midnight).
- Desative outros addons que substituem a janela de conversa (por exemplo, DialogueUI ou Immersion). Dois addons tentando controlar a mesma janela entram em conflito.

## Instalação

1. Baixe o repositório [nerdwow_worldofwarcraft_addonLore](https://github.com/ThiagoGregson/nerdwow_worldofwarcraft_addonLore) em **Code → Download ZIP** e extraia o arquivo.
2. Copie **apenas a pasta `NerdWow`** para:
   `World of Warcraft\_retail_\Interface\AddOns\`
3. Feche e abra o jogo de novo. Na tela de personagens, em **AddOns**, confira se o NerdWow está ativado.

Para atualizar, substitua a pasta `NerdWow` pela versão nova e reinicie o jogo. O seu diário não é apagado.

## Como usar

### Na conversa com um NPC

| Ação | Como fazer |
| --- | --- |
| Escolher uma opção | Clique nela ou use as teclas **1** a **9** |
| Mostrar a fala inteira de uma vez | **Espaço** |
| Fechar a conversa | **Esc** ou o **×** no canto superior direito |
| Ler uma fala longa | Role o mouse sobre o texto |

Ao escolher uma missão, o pergaminho abre à direita e mantém a legenda do NPC visível.

As opções permanecem na barra inferior; quando necessário, a fala e as opções têm rolagens independentes, com indicação para continuar a leitura. A dica de teclas acompanha as ações disponíveis.

### Na missão

| Momento | Como usar |
| --- | --- |
| Oferta | **Aceitar** ou **Recusar**; nas missões já aceitas automaticamente, apenas **Confirmar** |
| Progresso | **Continuar** fica disponível quando a missão puder ser entregue; **Voltar depois** fecha a leitura |
| Conclusão | Clique numa recompensa ou use **1–9**, depois **Concluir**; uma única opção já vem selecionada |
| Ler e comparar | Role o mouse sobre o papel e passe sobre os itens para ver o tooltip |
| Completar a fala ou fechar | **Espaço** completa a legenda; **Esc** ou **×** fecha a missão |

O pergaminho ajusta a altura ao conteúdo e rola quando chega ao limite. Nos itens exigidos, mostra a quantidade necessária e a quantidade em posse quando disponível.

A nota no rodapé aparece quando a oferta ou o progresso foi registrado no diário. A conclusão é registrada após a entrega confirmada pelo jogo. O arquivo em disco continua sendo gravado ao sincronizar, usar `/reload` ou sair do jogo.

`/nerdwow dialogo` também liga e desliga o pergaminho. Em combate, em caso de falha ou numa missão que exija uma confirmação especial da Blizzard (como PvP ou custo de entrega), a interface nativa fica disponível.

### Botão do minimapa

- **Clique:** sincroniza o diário (pede confirmação e recarrega a interface).
- **Arrastar:** move o botão pela borda do minimapa.
- **Passar o mouse:** mostra a versão, o total de eventos e quantos ainda não foram gravados.

### Comandos

| Comando | O que faz |
| --- | --- |
| `/nerdwow` | Mostra o status do diário |
| `/nerdwow ajuda` | Lista os comandos |
| `/nerdwow sincronizar` | Grava o diário em disco (recarrega a interface) |
| `/nerdwow botao` | Oculta ou mostra o botão do minimapa |
| `/nerdwow dialogo` | Liga ou desliga o cinema e o pergaminho de missão |
| `/nerdwow diagnostico` | Mostra os últimos erros registrados |
| `/nerdwow fontes` | Testa as fontes do addon (para relatar problemas) |

## O seu diário e a sua privacidade

- O diário fica no seu computador, em:
  `World of Warcraft\_retail_\WTF\Account\<sua conta>\SavedVariables\NerdWow.lua`
- O jogo só grava esse arquivo quando você **sincroniza**, usa `/reload`, sai do personagem ou fecha o jogo. Se o jogo travar ou cair, os eventos ainda não gravados podem se perder.
- Addons de WoW não têm acesso à internet: nenhuma informação sai do seu computador.
- O diário guarda os **5000 eventos mais recentes**. Os mais antigos são descartados automaticamente.
- Para apagar o diário, feche o jogo e exclua o arquivo `NerdWow.lua` dessa pasta.
- A sincronização não funciona durante o combate. Saia do combate e tente de novo.

## Problemas comuns

**A conversa em modo cinema não aparece**
1. Confira se ela está ligada com `/nerdwow dialogo`.
2. Desative outros addons de conversa, como o DialogueUI.
3. Use `/nerdwow diagnostico` para ver o erro registrado e inclua essa informação ao [relatar o problema](https://github.com/ThiagoGregson/nerdwow_worldofwarcraft_addonLore/issues).

Se algo der errado, o NerdWow devolve a conversa para a janela da Blizzard, então você nunca fica preso numa conversa.

**O jogo diz que o addon está desatualizado**
Isso acontece logo depois de uma atualização do jogo. Na lista de AddOns, marque **Carregar addons desatualizados** até sair uma versão nova do NerdWow.

## Créditos

- Fonte **Cinzel**, de Natanael Gama, e fonte **EB Garamond**, de Georg Duffner e Octavio Pardo. As duas são distribuídas sob a SIL Open Font License, incluída na pasta `NerdWow/Fonts`.
- Inspirado na experiência do addon DialogueUI, de Peterodox. Nenhum código ou arte dele foi usado.

## Direitos

© [gregson.com.br](https://gregson.com.br). Todos os direitos reservados.

O código está disponível para leitura, como exige a política de addons da Blizzard, mas não é distribuído sob nenhuma licença de uso, modificação ou redistribuição. Para qualquer uso além de instalar e jogar, entre em contato pelo [gregson.com.br](https://gregson.com.br). As fontes incluídas mantêm a própria licença (OFL).

O NerdWow não é afiliado nem endossado pela Blizzard Entertainment. World of Warcraft é marca registrada da Blizzard Entertainment, Inc.
