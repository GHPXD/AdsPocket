# Arquitetura

## Estrutura

```text
lib/
  main.dart                       inicialização e falha recuperável de armazenamento
  app/
    app.dart                      MaterialApp, IndexedStack, back Android, fila de compartilhamento
    app_controller.dart           estado e casos de uso locais
    theme.dart                    temas Material 3
  core/
    meta_ads_library_url_builder.dart
    native_bridge.dart            contrato MethodChannel
    widgets.dart                  estados vazios, confirmações e tratamento de erros
  data/
    models.dart                   modelos imutáveis e IDs locais aleatórios
    local_repository.dart         SQLite
    backup_service.dart           JSON versionado e validação
  features/
    explore/                      pesquisa, filtros e atalhos
    browser/                      WebView, política de navegação e modos visuais
    favorites/                    listagem, busca, edição e imagens
    history/                      histórico pesquisável
    settings/                     preferências e manutenção
android/app/src/main/kotlin/.../MainActivity.kt
                                  intents e Storage Access Framework
```

`ChangeNotifier` com `ListenableBuilder` mantém o estado de forma leve, sem framework adicional. `IndexedStack` preserva as telas. O WebView só é montado após a primeira visita à Biblioteca; uma chave estável mantém seu controller. Rebuilds de widgets Flutter não recriam a plataforma nativa nem recarregam uma URL. Um número sequencial identifica pedidos explícitos de navegação; atualizações observadas de URL não disparam novos carregamentos.

## Fluxo real de dados

Explorar → URL Builder → histórico SQLite → WebView oficial (ou navegador escolhido). A seleção de anunciantes acontece nos controles da Meta. A observação da URL identifica `view_all_page_id`, preserva o link original e salva a última Página visitada. Favoritos nunca dependem de dados extraídos de cards. Não há busca remota de nomes, scraping, API comercial simulada, polling ou backend.

`Bookmark` unifica a persistência dos tipos `advertiser`, `search`, `ad`, `offer` e `image`. Os nomes de domínio `AdvertiserBookmark`, `SavedSearch` e `SavedAdReference` são aliases desse modelo compartilhado. `SearchHistory` é separado. `UserSettings` fica em shared_preferences, validado antes da escrita.

## Persistência e migração

SQLite `adspocket.db`, esquema versão 1:

- `bookmarks`: ID local, identidade canônica única, JSON do modelo.
- `history`: ID local, URL canônica única, data indexável para ordenação, JSON do modelo.

As consultas de dados usam parâmetros. Repetir uma pesquisa atualiza a visita mantendo o ID. O histórico mantém no máximo 500 registros. Favoritos são únicos por tipo e URL; edição explícita conserva o ID. A importação usa transação e `INSERT OR IGNORE` para ambos os conflitos (ID e identidade), sem sobrescrever. Toda entrada é validada antes de abrir a transação.

A migração usa `OpenDatabaseOptions.version` e `onUpgrade`; uma mudança futura exige incrementar `schemaVersion` e adicionar passos ordenados, transacionais e testados. A versão atual não tenta converter esquemas desconhecidos nem apaga dados automaticamente. Não há migração fictícia de uma versão que ainda não existe.

## Android e arquivos

`MainActivity` recebe `ACTION_SEND` (texto/imagem) e `ACTION_VIEW` (links HTTPS da Biblioteca). A fila de até 20 itens é guardada em preferências privadas até o Dart consumi-la. `onNewIntent` atende novas entregas com o processo ativo; a inicialização consome entregas a frio. Conteúdo é confirmado na interface antes de abrir/salvar.

O canal `app.adspocket/native` oferece `pendingShares`, `importBackup`, `exportBackup`, `pickImage`, `imagePath`, `deleteImage` e `openBrowser`. JSON usa `ACTION_OPEN_DOCUMENT` / `ACTION_CREATE_DOCUMENT`; não há acesso amplo ao armazenamento. Leitura limitada a 5 MB para backups, 15 MB para imagem e 40 megapixels. Imagens têm cabeçalho e dimensões validados, recebem nome UUID e são copiadas para `files/references`. Caminhos arbitrários nunca vêm do JSON. I/O nativo usa executor dedicado.

## Segurança e privacidade

Entradas de maior risco: links externos, compartilhamentos e backups. URLs da Biblioteca exigem HTTPS, hosts exatos permitidos, caminho `/ads/library`, ausência de credenciais e porta padrão; IDs públicos são numéricos. Esquemas `javascript:`, `intent:`, `file:`, HTTP e hosts enganadores são rejeitados. Links fora da Biblioteca pedem confirmação antes da abertura externa. Erros TLS não são ignorados, permissões de câmera/microfone são negadas, acesso a arquivos pelo WebView está desativado, e conteúdo misto é bloqueado.

Não há leitura de cookies, senhas ou tokens. Cookies normais permanecem sob gestão do WebView. O app não cria tela de login, não altera User-Agent manualmente para superar bloqueios e não injeta CSS. O modo desktop solicita uma preferência nativa de conteúdo; não garante suporte do site. Há apenas verificação conservadora de página em branco e comando de saída de mídia em tela cheia, sem extração de anúncios. A única permissão de plataforma solicitada é INTERNET; o manifesto final também inclui a permissão privada de receiver gerada pelo AndroidX. Backup automático Android está desabilitado.

