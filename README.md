# NerdWow

**Para quem joga World of Warcraft pela história.** O NerdWow transforma as conversas com NPCs em cenas de cinema e guarda num diário tudo o que o seu personagem vive: os lugares por onde passa, as missões que aceita e conclui e as conversas que tem pelo caminho.

> **Status:** em desenvolvimento (alfa). Funciona apenas no **Retail (Midnight)**. A interface e os textos do addon estão em português do Brasil.

## O que ele faz

**Conversas em modo cinema**
- Substitui a janela de conversa da Blizzard: barras de cinema, nome e brasão do NPC, e a fala aparecendo letra a letra.
- Opções numeradas, que podem ser escolhidas pelas teclas **1 a 9**.
- O visual muda conforme o lugar e o NPC: **Aliança**, **Horda**, **Quel'Thalas** ou **Neutro**.

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

- Pergaminho de missão à direita da tela, com objetivos e recompensas.
- Câmera cinematográfica no NPC durante a conversa.
- Narração das falas por voz (TTS).
- Registro das falas de NPCs no chat.

## Requisitos

- World of Warcraft **Retail**, patch **12.1.5** (Midnight).
- Desative outros addons que substituem a janela de conversa (por exemplo, DialogueUI ou Immersion). Dois addons tentando controlar a mesma janela entram em conflito.

## Instalação

1. Baixe este repositório em **Code → Download ZIP** e extraia o arquivo.
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

Ao escolher uma missão, ela abre na janela de missão do jogo (o pergaminho próprio ainda está em desenvolvimento).

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
| `/nerdwow dialogo` | Liga ou desliga a conversa em modo cinema |
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
3. Use `/nerdwow diagnostico` para ver o erro registrado e inclua essa informação ao relatar o problema.

Se algo der errado, o NerdWow devolve a conversa para a janela da Blizzard, então você nunca fica preso numa conversa.

**O jogo diz que o addon está desatualizado**
Isso acontece logo depois de uma atualização do jogo. Na lista de AddOns, marque **Carregar addons desatualizados** até sair uma versão nova do NerdWow.

## Créditos

- Fonte **Cinzel**, de Natanael Gama, e fonte **EB Garamond**, de Georg Duffner e Octavio Pardo. As duas são distribuídas sob a SIL Open Font License, incluída na pasta `NerdWow/Fonts`.
- Inspirado na experiência do addon DialogueUI, de Peterodox. Nenhum código ou arte dele foi usado.

## Direitos

© Greg. Todos os direitos reservados. O código está disponível para leitura, como exige a política de addons da Blizzard, mas não é distribuído sob nenhuma licença de uso, modificação ou redistribuição. As fontes incluídas mantêm a própria licença (OFL).

O NerdWow não é afiliado nem endossado pela Blizzard Entertainment. World of Warcraft é marca registrada da Blizzard Entertainment, Inc.
