# Arquitetura

## Adições da 1.2.0

`core/pocket_icon.dart` desenha a identidade vetorial; `pocket_grid.dart` fornece grades responsivas. `features/research/research_engine.dart` contém catálogo, combinações, provedores, detecção, validação dos novos registros e agrupamento; `research_screen.dart` contém os fluxos de pesquisa. Catálogo versionado em `assets/knowledge`, reconstruível por `tool/import_research_catalog.py`.

SQLite v3 adiciona `research` por migração aditiva; backup v3 aceita versões anteriores. O controlador carrega pesquisas e integra exportação/mesclagem. Não há nova dependência ou servidor. [Modelo de evidência](EVIDENCE_MODEL.md) e [Detecção](TECHNOLOGY_DETECTION.md) detalham contratos e limites.

## Estrutura

```text
lib/
  main.dart                       inicialização e falha recuperável de armazenamento
  app/
    app.dart                      MaterialApp, 4 abas (IndexedStack), back Android, fila de compartilhamento
    app_controller.dart           estado global (ChangeNotifier), sessão, casos de uso locais, Tabs
    theme.dart                    temas Material 3
  core/
    meta_ads_library_url_builder.dart   construção/validação de URLs da Biblioteca
    longevity.dart                CivilDate, idade em dias civis, filtro local, status
    text_extraction.dart          datas PT/EN e preços em texto reconhecido; dinheiro
    ocr_engine.dart               interface OcrEngine + ML Kit (substituível em testes)
    native_bridge.dart            contrato MethodChannel
    widgets.dart                  estados vazios, confirmações, tratamento de erros
  data/
    models.dart                   Bookmark, SearchHistory, UserSettings
    offer.dart                    Offer (Mineração), PriceRange, OpportunityScore
    local_repository.dart         SQLite v3 e migrações aditivas
    backup_service.dart           JSON v1/v2/v3, CSV, política para ZIP
  features/
    explore/                      pesquisa, filtros, atalhos, retomada
    browser/                      WebView, toolbar, modos, imersivo, erros, assistente (library_assistant.dart)
    saved/                        aba Salvos (Anúncios | Anunciantes | Outros)
    mining/                       lista de anúncios, filtros, editor, detalhe, OCR, revisão, comparador
    favorites/                    anunciantes e outros, fluxo "Salvar referência"
    history/                      histórico pesquisável
    settings/                     ajustes e manutenção
android/app/src/main/kotlin/.../MainActivity.kt   intents, SAF, imagens validadas
```

`ChangeNotifier` + `ListenableBuilder`, sem framework adicional. Abas: `Tabs.explore`, `library`, `saved`, `settings`.

## WebView

`BrowserScreen` é montado na primeira visita e mantido no `IndexedStack`; a chave estável preserva o controller. Pedidos explícitos de navegação incrementam `navigationSerial`; observações de URL nunca disparam carregamentos. `_loadPending` compara a URL canônica atual e ignora pedidos duplicados.

`jumpTo(target)` procura a URL no histórico do WebView (`getCopyBackForwardList`) e usa `goBackOrForward`, preservando rolagem e estado da página; só carrega de novo quando a entrada não existe. É usado por "Voltar à pesquisa" e pelo chip Página ↔ Pesquisa.

`AppController.observeUrl` persiste `lastUrl`; URLs com `view_all_page_id` viram `lastAdvertiser`; URLs com `q` viram `initialSearch` (o retorno da pesquisa). Com "Retomar a última pesquisa", `currentUrl` inicial é `lastUrl`. A pilha do WebView não sobrevive ao encerramento do processo.

Modo imersivo: `AppController.libraryChromeHidden` remove o `NavigationBar` quando a aba é a Biblioteca; a toolbar continua abaixo do WebView (nunca sobreposta). Desktop: `preferredContentMode` + `reload()` na troca. Teclado aberto: cabeçalho e toolbar saem para dar espaço.

`loadsCompleted` e `failed` são estados públicos do `BrowserScreenState` usados pelos testes de integração como condições verificáveis (não logs).

## Assistente da Biblioteca

`assistantScript` é injetado como `UserScript` (fim do documento) e só age em `/ads/library`. Ele encontra cada card pelo texto "Library ID" e sobe na árvore até o maior ancestral com um único ID (independe de classes CSS). Envia ao app, pelo handler `adspocket`, apenas o texto visível do card (ID, linha de início, ativo, anunciante, texto, variações, vídeo, links de perfil e de vendas) e a contagem visível de resultados com a URL da medição. Um `MutationObserver` com debounce acompanha a rolagem; cards que saem da página são descartados.

O app valida e limita tudo (`LibraryCard.fromJson`, `parseAssistantMessage`), calcula as idades em dias civis no Dart e devolve `AdsPocketAssist.apply({ages, saved, minDays, includeUndated, minAds})`; `minAds` compara com o "N ads use this creative and text" do card (1 quando ausente). O script desenha a barra de ações do card (Salvar, Página, Copiar, Compartilhar, selo de dias/anúncios; ícones SVG criados por DOM, sem `innerHTML`) e oculta, de forma reversível, os cards fora do filtro. Salvar, Copiar e Compartilhar chamam o handler; `LibraryCard.toOffer` cria a referência (identidade `ad:<Library ID>`, sem duplicar). `autoScroll(n)` rola até achar mais n cards no filtro. `disable()` remove selos e restaura os cards. O `MutationObserver` usa *throttle* de 700 ms (não *debounce*), porque vídeos e contadores mudam a página o tempo todo e adiariam a leitura indefinidamente.

**Botão Página.** O link do anunciante no card é o ID do perfil, que muitas vezes difere do Page ID da Biblioteca. `findPage(id)` clica em "Ver detalhes do anúncio", espera o diálogo com aquele Library ID, expande "Sobre o anunciante", lê "Identificação: N" do texto visível, fecha o diálogo e envia `{type: 'page', id, page, name}`. O Dart valida (só dígitos), guarda `pageOfAd` e `pageByProfile` (devolvidos ao script em `apply({pages})` para não reabrir detalhes) e abre `MetaAdsLibraryUrlBuilder.build(type: pageId, status: active)`. Sem ID nos detalhes, `suggest(card)` preenche o campo de busca da Meta com o nome do anunciante (setter nativo + evento `input`), espera a lista `role=listbox` e destaca com `outline` a opção cujo texto contém o @ do link do perfil (ou a única com o mesmo nome); envia `pick: true`. O app avisa para tocar no destaque e guarda `pendingPick`; quando a URL seguinte trouxer `view_all_page_id` em até 2 min, o ID é associado ao anúncio e ao perfil. A seleção não é automatizada: a Meta ignora cliques sintéticos nessa lista e o app não simula toques. O Page ID descoberto também vai para o anúncio salvo.

**Modo Feed.** `ViewMode.feed` faz `libraryChromeHidden` e remove cabeçalho, barra do assistente e toolbar; um controle flutuante (`AnimatedSlide`, escondido em `onScrollChanged` ao descer) dá acesso a Voltar, filtros, Auto-rolar e Sair. `AdsPocketAssist.feed(true)` troca `position: sticky` por `static` nas barras largas da Meta fora dos cards e diálogos (guardando o valor em `data-adspocket-pin`); `feed(false)` restaura. O script não usa cookies, armazenamento nem rede (há teste que impede).

A contagem da Meta só é gravada num anunciante (`metaAdCount`, `metaAdCountAt`) quando a URL da medição tem o mesmo Page ID.

## Favoritos e identificação

`saveCurrentReference(uri)` é o único caminho do botão Salvar: com Page ID abre o formulário de anunciante identificado; sem Page ID abre o diálogo de quatro opções. `askPageIdUrl` valida dígitos, constrói a URL e exige confirmação. `Bookmark.validateKind` impede, no repositório, gravar `advertiser` sem Page ID igual ao da URL. `Bookmark.identifyAs` reclassifica mantendo ID, nome, tags e notas e guarda a URL anterior em `sourceUrl`.

## Persistência e migração

SQLite `adspocket.db`, esquema **versão 2**:

- `bookmarks` (v1): ID, identidade canônica única, JSON.
- `history` (v1): ID, URL canônica única, data, JSON.
- `offers` (v2): ID, identidade única opcional (`ad:<id público>`), `updated_at`, JSON.
- `visits` (v2): visitas por anunciante (máx. 100 por anunciante), índice por anunciante/data.

`onUpgrade` 1→2 roda dentro da transação do sqflite: cria as tabelas e reescreve no lugar cada `advertiser` legado. Com Page ID na URL → recebe `pageId`; sem → `unidentified` com `legacyKind = advertiser`. Nenhum registro é apagado e nenhum ID é inventado. Falha reverte tudo. `LocalRepository.createV1` reproduz o esquema 1.0.0 para testes de migração.

Campos novos de `Bookmark` e `UserSettings` são opcionais no JSON, então dados e preferências da 1.0.0 carregam sem conversão. Consultas são parametrizadas; gravações usam transações.

## Datas, longevidade e score

`CivilDate` guarda ano/mês/dia; idade = diferença entre meia-noites UTC das duas datas civis, imune a fuso e horário de verão. A data de hoje vem do relógio local do aparelho. `LongevityFilter` age só sobre `Offer.startDate` catalogado; data futura nunca passa num filtro de idade. Data de início, data de captura, última visita e última verificação são campos distintos.

`OpportunityScore` soma apenas critérios com dados e expõe `coverage` (pontos possíveis cobertos) e `pending`. Moeda diferente da faixa não é comparada.

## OCR

`OcrEngine.recognize(path)` retorna linhas com caixas em pixels da imagem. A seleção de região filtra linhas pelo centro da caixa. `findDateCandidates` encontra datas e procura frases de início apenas entre a data anterior e a atual (para não atribuir a frase de um anúncio ao próximo). `DateSuggestion.preselected` só existe com uma única frase de início não ambígua; mesmo assim o usuário confirma.

## Android e arquivos

Canal `app.adspocket/native`: `pendingShares`, `importBackup`, `exportBackup`, `exportFile` (JSON/CSV via `ACTION_CREATE_DOCUMENT`, nome validado), `pickImage`, `imagePath`, `saveImageBytes` (captura do WebView, mesma validação de importação: assinatura PNG/JPEG/WebP, ≤15 MB, ≤40 MP, nome UUID), `deleteImage`, `openBrowser`. Imagens não referenciadas são removidas ao cancelar fluxos.

## Segurança e privacidade

URLs da Biblioteca: HTTPS, hosts exatos, `/ads/library`, sem credenciais, porta padrão, IDs numéricos. Links externos pedem confirmação. Permissões de câmera/microfone do site negadas; acesso a arquivos do WebView desativado; conteúdo misto bloqueado; TLS inválido cancelado. O app não lê cookies, senhas ou tokens, não injeta folhas de estilo e não altera o User-Agent. Em produção, o DOM é lido pelo assistente (texto visível dos cards e, sob toque no botão Página, do diálogo de detalhes) e pela verificação de página em branco; os testes live leem texto do DOM para conferir os resultados. CSV neutraliza fórmulas. `ArchivePolicy` rejeita caminhos absolutos, `..`, barras invertidas, letras de unidade, nomes fora do padrão, duplicatas e tamanhos excessivos.

## Build e distribuição

Release: `ADSPOCKET_KEYSTORE`, `ADSPOCKET_KEYSTORE_PASSWORD`, `ADSPOCKET_KEY_ALIAS`, `ADSPOCKET_KEY_PASSWORD` ativam a assinatura própria; sem elas, a chave de debug local (a mesma da 1.0.0) é usada. `proguard-rules.pro` suprime avisos dos reconhecedores opcionais do ML Kit. `.github/workflows/android.yml` gera o APK como artefato e um rascunho de release para tags `v*`.
