# Validação — 1.2.0+3

Data: 29/10/2026. Windows, Flutter 3.47.2/Dart 3.13.2, Java 21; emulador Android 15 `WeSyncAd`. Nenhum aparelho físico conectado.

| Verificação | Resultado |
|---|---|
| `dart format --output=none --set-exit-if-changed` | 51 arquivos; zero alterações |
| Linha de base 1.1.0 antes das mudanças | 106 testes aprovados |
| `flutter analyze --no-pub` | Sem problemas |
| `flutter test --no-pub` | 118 testes aprovados |
| `integration_test/research_test.dart` | Aprovado no Android; duas verificações funcionais mais o encerramento da suíte |
| APK release com `lib/main.dart` | Compilado, versão 1.2.0/code 3; 92.075.948 bytes |
| Assinatura | Verificada com apksigner; certificado igual ao APK 1.1.0 local |
| Instalação e abertura release | `adb install -r`: Success; tela inicial visível, sem FATAL EXCEPTION/E/flutter no processo durante a conferência |

A suíte nova cobre catálogo/procedência, normalização de acentos e moeda, presets, combinações/deduplicação/exclusão, domínios enganosos, limites, agrupamento de produtos distintos, CRUD, backup v3, validação antes de importar, migração real de banco v2 e reabertura. Widgets verificam hub em 320/411/760 dp a 1,8x; a suíte existente mantém telas estreitas, temas, OCR com vários candidatos, revisão, comparação, filtros e navegação.

No Android: navegação pelo hub, escolha de nicho/subnicho, geração/salvamento de pacote, detecção de checkout, salvamento de evidência, exportação JSON em memória e persistência após reabrir o banco. Banco de QA com nome aleatório e preferências simuladas; dados pessoais não são limpos. Uma segunda verificação executa o assistente num WebView real com fixture local: quantidade ausente não vira 1, filtro mínimo exige valor conhecido, datas ausentes obedecem à inclusão e cards reaparecem ao remover filtros.

Capturas reais: `docs/screenshots/120-explorar-escuro.png`, `120-explorar-claro.png`, `120-pesquisa-360.png`, `120-construtor.png`, `120-detector.png`. A conferência final do release está em `dist/release-smoke-1.2.0.png` (ignorado pelo Git). Hash SHA-256 do APK: `8426cea04d64e6e0ccd4606a6a556977d6d3ad8926c08da526f9991e736a6f9c`. Logs locais: `analyze-1.2.log`, `tests-1.2.log`, `build/research_test.log` (ignorados pelo Git).

A verificação live da Meta **não foi repetida nesta rodada**. Os resultados abaixo pertencem à 1.1.0. Compartilhamento/exportação pelo seletor Android e aparelho físico permanecem sem uma nova validação nesta versão; os caminhos nativos existentes são preservados. Fases 2/3 não são declaradas entregues.

Para repetir a suíte Android: `bash tool/android_tests.sh integration_test/research_test.dart emulator-5554`. Execute comandos Flutter e builds em sequência. Depois de `flutter drive`, compile release com a resolução de dependências padrão (sem `--no-pub`) para regenerar o registrador de plugins sem o plugin de integração.

## Histórico de validação — 1.1.0

Data: 28–29/10/2026 (America/Sao_Paulo). Versão testada: 1.1.0+2.

Atualização de 29/10: barra de ações por card, botão **Página**, **modo Feed** e a Meta em **português** (emulador em pt-BR). Os resultados abaixo são da execução mais recente.

## Ambiente

- Windows 11 Pro, Flutter 3.47.2 stable, Dart 3.13.2, Java 21, AGP 8.13.2, Gradle 8.14.3, Kotlin 2.2.20.
- Emulador `WeSyncAd` (Pixel, x86_64), **Android 15**, Android System WebView **124.0.6367.219**, rede real até a Meta (país BR). Idioma do sistema **pt-BR**: a Meta é exibida em português ("Identificação da biblioteca", "Veiculação iniciada em", "N anúncios usam esse criativo e esse texto").
- **Nenhum aparelho físico conectado.** Nada abaixo vale como aprovação em aparelho físico.

## Linha de base antes das alterações

`flutter analyze`: sem problemas. `flutter test`: **33 aprovados** (código 1.0.0 inalterado).

## Resumo

| Categoria | Resultado |
|---|---|
| `dart format --set-exit-if-changed` | **APROVADO** (0 arquivos alterados) |
| `flutter analyze` | **APROVADO** — No issues found |
| `flutter test` (host) | **TESTE AUTOMATIZADO APROVADO — 106 testes** |
| `integration_test/app_test.dart` (Android, determinístico) | **TESTE AUTOMATIZADO APROVADO** no emulador |
| `integration_test/live_meta_test.dart` (Android, Meta real) | **TESTE LIVE APROVADO** no emulador, com screenshots |
| `flutter build apk --debug` / `--release` | **APROVADOS** |
| Atualização 1.0.0 → 1.1.0 sem desinstalar | **APROVADO** no emulador |
| Galaxy S23 Ultra / aparelho físico | **TESTE NÃO EXECUTADO** (sem aparelho) |
| Workflow GitHub Actions | **TESTE NÃO EXECUTADO** (nenhum push feito) |
| Seletores SAF (exportar/importar arquivo) e folha de compartilhamento | **TESTE NÃO EXECUTADO** manualmente; lógica coberta no host |
| OCR com ML Kit real em print real | **TESTE NÃO EXECUTADO** no aparelho; parser e tela testados com motor falso |

## Testes automatizados no host (106)

| Arquivo | Cobertura |
|---|---|
| `test/url_builder_test.dart` (23) | Construção e validação de URLs, hosts enganosos, host regional `web.facebook.com`, `sameView` após reescrita de URL pela Meta, ID de link de perfil |
| `test/data_test.dart` (11) | SQLite, deduplicação, SQL como dado, backup v1/v2, rejeições, merge sem sobrescrita, preferências |
| `test/longevity_test.dart` (10) | Datas civis, limite exato, todos os presets, sem filtro, data desconhecida, data futura, 0–365, mudança de dia, horário de verão, status e verificação antiga |
| `test/ocr_text_test.dart` (14) | Frases de início PT/EN (6 formatos), frase quebrada em linhas, numérico ambíguo, data sem contexto, vários anúncios, texto sem data, região, dinheiro, preços OCR |
| `test/offer_test.dart` (11) | Validação, JSON, identidade/duplicatas, score com cobertura, faixa low ticket, filtros combinados, ordenação, CSV, política ZIP |
| `test/migration_test.dart` (9) | Banco **v1 real → v2**: registros preservados, reclassificação só com evidência, correção manual, não migra duas vezes; anunciante sem Page ID rejeitado; pesquisa e não identificada coexistem; duplicatas; ofertas; visitas; backup 1.0.0; backup 2 sem caminhos de imagem; restauração de sessão |
| `test/flows_test.dart` (16) | Modo Feed: sem navegação/cabeçalho/toolbar, controle flutuante, filtros pelo controle, sair restaura. |
| (continuação) | Salvos (contador, preço, seções); salvar card em 1 toque + comentário + sem duplicar; barra do assistente (dias por preset e personalizado com validação 0–365, quantidade por preset e personalizado, sem "Só ativos", desligar); pílulas do Explorar (`media_type`, idade); e os fluxos abaixo |
| (continuação) | Salvar com Page ID; sem Page ID → diálogo de 4 opções (cancelar, pesquisa, não identificada); Page ID manual com validação e confirmação; Mineração (vazio, contador "filtro local", ≥14 dias, preço, limpar); revisão rápida com desfazer; OCR com dois anúncios exige escolha; imersivo; toolbar e modo compacto; todas as abas em escuro/claro, texto 1,6×/2× e 320/360 dp |
| `test/library_assistant_test.dart` (8) | Card → anúncio completo; rótulos PT, intervalo de inativo, sem data; dados da página não confiáveis (ID, links inseguros, tamanhos); mensagens malformadas; comando de filtro com Page IDs conhecidos; mensagem `page` validada (só dígitos, sem ID inventado, caminho de escolha na lista); script sem cookies/armazenamento/rede, sem `innerHTML`, sem clique sintético na lista de anunciantes, modo Feed por `position: static`, *throttle* do observador |
| `test/widget_test.dart` (4) | Testes 1.0.0 atualizados (aba "Ajustes", espera por condição em vez de atraso fixo) |

Nenhum teste usa cards de anúncio falsos. O OCR de host usa um motor falso só para fornecer linhas de texto; o reconhecimento ML Kit real não roda no host.

## Android determinístico — `integration_test/app_test.dart`

Executado com `bash tool/android_tests.sh integration_test/app_test.dart emulator-5554`. **All tests passed.** Asserts (não logs):

- WebView criado; carga concluída (`loadsCompleted`), sem erro principal (`failed == false`); URL válida da Biblioteca com `q=planilha`.
- Mesma instância do controller após alternar abas.
- Botão Salvar numa pesquisa abre "Não foi possível identificar uma Página nesta URL."; cancelar não salva nada.
- Abrir Página → URL com o Page ID; voltar à pesquisa pelo chip **Pesquisa** move no histórico (Avançar fica disponível, sem nova entrada).
- Avançar volta à Página; salvar cria anunciante identificado com Page ID.
- Carga em host inexistente → tela "Não foi possível carregar a Biblioteca" com "Abrir no navegador"; "Tentar novamente" recupera a Página.
- Modo imersivo remove e devolve o `NavigationBar`.
- Reinício (banco fechado e reaberto, app recriado): histórico, favorito, Page ID e última URL persistem; reabrir o favorito carrega a Página certa, atualiza última visita e registra 1 visita.

Capturas: `01-explorar.png`, `03-erro-carregamento.png`, `02-reabertura-favorito.png`.

## Validação live da Meta — `integration_test/live_meta_test.dart`

Executado com `bash tool/android_tests.sh integration_test/live_meta_test.dart emulator-5554`. **All tests passed.** O teste falha se não houver cards reais: exige no texto renderizado ao menos um Library ID ("Identificação da biblioteca: <número>") **e** uma data de início. Leitura do DOM existe só no teste, para verificar o que o usuário vê.

| Passo | Resultado | Evidência |
|---|---|---|
| 1-3 Pesquisar "planilha" pelo Explorar | APROVADO | `10-live-explorar.png` |
| 4 Anúncios reais nos resultados | **APROVADO** — 30 cards com Library ID, 30 datas de início, 26 vídeos, ~18.000 resultados exibidos pela Meta | `11-live-resultados.png` |
| Assistente: leitura dos cards | **APROVADO** — 30 cards lidos, 30 com data, contagem "~18,000/~19,000" exibida | `11b-live-assistente-filtro.png` |
| Assistente: filtro 30+ dias | **APROVADO** — cada card visível tinha ≥ 30 dias, cada oculto < 30 (25 visíveis, 5 ocultos) | `11b-live-assistente-filtro.png` |
| Assistente: filtro de quantidade 2+ | **APROVADO** — contagens lidas dos cards {1: 18, 2: 4, 5: 1, 8: 2, 15–24: 5}; 12 visíveis, todos com 2+; 18 ocultos, todos com 1 | `11e-live-filtro-quantidade.png` |
| Assistente: Salvar com toque real | **APROVADO** — Sólides Educação, Library ID e início 08/07/2025 lidos do card, ativo; botão virou "Salvo no AdsPocket" (verde) | `11c-live-salvo-1-toque.png` |
| Assistente: auto-rolagem | **APROVADO** — 40 → 50 cards carregados da Meta | `11d-live-auto-rolagem.png` |
| Barra de ações por card | **APROVADO** — Salvar, Página, Copiar, Compartilhar e selo "478 DIAS" | `21-live-acoes-do-card.png` |
| Botão Página (ID nos detalhes) — manual, toque real | **APROVADO** — anúncio 2915138038839875 (o do seu print) → "Sobre o anunciante: Identificação 106480812544708" → `view_all_page_id=106480812544708`, Sublime Concursos, ~78 na Meta. O link do perfil no card era `100095412855531` | `22a-live-pagina-pelo-card-id.png` |
| Botão Página (Página sem ID nos detalhes) — teste automatizado, toques reais | **APROVADO** — Sólides Educação: nome digitado na busca da Meta, opção @solides.rhportal destacada, toque real → `view_all_page_id=266919370074481`, `active_status=active`, nome na Página; ID associado ao anúncio | `21b-live-escolher-anunciante.png`, `22-live-pagina-pelo-card.png` |
| 5 Selecionar Página: digitação real (`adb input text`) do anunciante no campo da Meta e toque real na sugestão "Advertisers" | **APROVADO** — Victor Pareto, Page ID 468037109734919 | `12-live-sugestao-anunciante.png` |
| 6 Página correta | **APROVADO** — URL com o Page ID e nome do anunciante na página | `13-live-pagina-anunciante.png` |
| 7 Anúncios da Página | **APROVADO** — 29 cards com Library ID e data (~180 resultados) | `13-live-pagina-anunciante.png` |
| 8-9 Abrir detalhes de um anúncio | APROVADO visualmente — modal "Ad Details" com texto, Library ID, data e mídia | `14` (modal carregando), `18` (modal carregado) |
| 10 Voltar à pesquisa pelo histórico | **APROVADO** — `q=planilha`, 32 cards, Avançar disponível | `15-live-retorno-pesquisa.png` |
| 11 Salvar anunciante | **APROVADO** — Page ID 468037109734919; contagem gravada "~180" = exibida na Página | `16-live-favoritos.png` |
| 12 Reabrir pelos Favoritos | **APROVADO** — Página com 31 cards; **0 recargas** porque já estava aberta | `17-live-reabertura.png` |
| 13 Page ID persistido | **APROVADO** — lido de novo do SQLite | — |
| Modo Feed | **APROVADO** — sem `NavigationBar`, cabeçalho e toolbar; 3 barras fixas da Meta passaram a rolar (0 elementos largos com `sticky`); controle some ao descer e volta ao subir; sair restaura as barras | `23-live-modo-feed.png`, `23a-live-modo-feed-topo.png`, `23b-live-modo-feed-rolando.png` |
| Modo compacto | Evidência visual: sem cabeçalho, mais área para a Biblioteca | `18-live-modo-compacto.png` |
| Modo desktop | **Meta/WebView não aplicou**: viewport 412 px antes e depois | `19-live-modo-desktop.png` |

Os anunciantes e a contagem de resultados variam com o tempo; o teste escolhe um anunciante presente no momento, não um ID fixo.

## Problemas encontrados e corrigidos durante a validação

1. **A 1.0.0 nunca exibia anúncios neste ambiente.** A Meta responde primeiro com uma página automática de verificação e redireciona para `https://web.facebook.com/ads/library/…&_rdc=1&_rdr`. A lista de hosts não aceitava `web.facebook.com`, então o app cancelava o redirecionamento e mostrava "Continuar no navegador?". O título "Ad Library" da página de verificação é o que o teste 1.0.0 registrava como sucesso. Correção: `web.facebook.com` na lista exata de hosts (e intent filter), com testes contra variações enganosas.
2. **A Meta reescreve a URL da pesquisa** (host, `is_targeted_country`, `media_type`, `sort_data`). "Voltar à pesquisa" não achava a entrada e recarregava. Correção: `sameView` (mesmo Page ID, ou mesma consulta e país).
3. **ID do link de perfil ≠ Page ID.** O perfil de Victor Pareto usa `61569677676829`; a Biblioteca usa `468037109734919`. Com o primeiro, a Meta mostrou "No ads match your search criteria". Correção: o diálogo de perfil explica que o número pode não ser o Page ID, a opção virou "Tentar como Page ID" e salvar um anunciante com esse ID exibe aviso. A seleção confiável é pela lista "Advertisers" da Meta.
4. **Toolbar continuava visível com o teclado aberto** (o `Scaffold` remove `viewInsets` do corpo). Correção: insets da janela + `didChangeMetrics`.
5. **Pop-ups de perfil** (`onCreateWindow`) não passavam pela mesma regra; corrigido.
6. **Página vazia de verificação** não era sinalizada; agora, sem texto após 12 s, aparece o aviso para continuar no navegador. O app não tenta contornar a verificação.
7. Parser de datas atribuía "Iniciado em" de um anúncio à data seguinte; a busca da frase agora para na data anterior.

8. Avisos com ação ("Comentar", "Desfazer") não sumiam (o Flutter os mantém por padrão) e cobriam a toolbar; agora somem em 4 s.
9. A contagem da Meta podia vir da vista anterior que a Meta mantém no DOM (gravou "~19,000" num anunciante com ~180). Agora só o contador visível conta, e só é gravado se medido na mesma Página.
10. Auto-rolagem parava na hora quando já havia anúncios suficientes no filtro; a meta passou a ser "mais N".
11. **Selos não apareciam em algumas páginas** (seu print de "Mapa mental"): o observador usava *debounce* e vídeos/contadores mudando a página o tempo todo adiavam a leitura indefinidamente. Agora é *throttle* de 700 ms. Também: texto normalizado (NFC) e diálogos ignorados na varredura.
12. **Quantidade em português não era lida**: o texto é "N anúncios usam esse criativo e esse texto" (com "esse" duas vezes). Regex corrigida; números com separador de milhar aceitos.
13. O clique do botão Página caía num invólucro sem ação (`role=none`); agora o alvo é o próprio botão ou o elemento mais interno com o texto.
14. A lista de anunciantes da Meta ignora cliques sintéticos; o app passou a destacar a opção e pedir o toque do usuário (sem simular toques).
15. Script lançava erro em página sem `body` (verificação automática da Meta); protegido.

## Builds

| Artefato | Bytes | SHA-256 |
|---|---:|---|
| `dist/AdsPocket-1.1.0.apk` (release) | 91.205.013 | `e80be6dd5618f4a42e01f578a11a6f6a96be7c676bb95be7a501e5dcb9c51542` |
| `dist/AdsPocket-1.1.0-debug.apk` | 214.833.967 | `c0f9e08d4ab4f52db687e20e518dc8d4ec8b344c41be25666b61a2c11f648eb2` |

`apksigner`: certificado `CN=Android Debug`, SHA-256 `8ddde2b0…1d56e4`, **o mesmo da 1.0.0**. `aapt`: versionCode 2, versionName 1.1.0, minSdk 24, targetSdk 36, ABIs arm64-v8a/armeabi-v7a/x86_64. Permissões: INTERNET, **ACCESS_NETWORK_STATE (nova, vinda do ML Kit)** e a permissão privada de receiver do AndroidX.

Atualização: 1.0.0 instalada limpa e iniciada (cria o banco v1) → `adb install -r AdsPocket-1.1.0.apk` = **Success** → início a frio `Status: ok`, processo ativo, tela Explorar (`20-release-1.1.0-atualizado.png`). O banco v1 criado pela 1.0.0 nesse ensaio estava vazio; a migração com dados é coberta pelo teste de host com banco v1 real.

## Roteiro manual — Galaxy S23 Ultra (pendente)

Instalar `AdsPocket-1.1.0.apk` por cima da 1.0.0 e marcar cada item como APROVADO/REPROVADO com print:

1. Rolagem longa nos resultados e na Página; fluidez a 120 Hz.
2. Pinça e "Texto do site" (75–200%).
3. Vídeos: reprodução, som, tela cheia, voltar da tela cheia.
4. Teclado no campo da Meta: toolbar e cabeçalho somem; voltam ao fechar.
5. Voltar físico/gesto: histórico do WebView, depois aba Explorar.
6. Alternar abas e voltar: mesma posição de rolagem.
7. Selecionar anunciante pela lista "Advertisers", salvar, reabrir por Salvos → Anunciantes.
11. Assistente: barra de ações, Salvar, **Página** (com e sem ID nos detalhes), filtro de dias e de quantidade, Auto-rolar com rolagem real a 120 Hz; **modo Feed** (controle some ao rolar).
8. Compartilhar link da Biblioteca e um print de outro app para o AdsPocket; "Analisar imagem" (OCR real), confirmar data, salvar na Mineração.
9. Modo imersivo e compacto; modo desktop (observar se a Meta muda o layout).
10. Exportar/importar JSON e CSV pelo seletor do Android.

## Comandos

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
bash tool/android_tests.sh integration_test/app_test.dart emulator-5554
bash tool/android_tests.sh integration_test/live_meta_test.dart emulator-5554
flutter build apk --debug --target=lib/main.dart
flutter build apk --release --target=lib/main.dart
```

`tool/android_tests.sh` precisa de `adb` no PATH (ou `ADB=...`), grava logs em `build/` e screenshots em `docs/screenshots/`. Execute builds e testes em sequência, não em paralelo.
