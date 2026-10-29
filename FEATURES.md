# Funcionalidades — versão 1.2.0

## Novidades da 1.2.0

Explorar minimalista com filtros recolhidos, ícones próprios e grids responsivos. Pesquisa 360° reúne taxonomia, 449 expressões com origem, construtor, dez presets, pacotes locais com JSON, dez fontes assistidas, checkouts/tecnologias, dossiês/evidências e agrupamento conservador. Leia [Método](MINING_METHODOLOGY.md), [Palavras-chave](MINING_KEYWORDS.md) e [Fontes](MINING_SOURCES.md).

Quantidade ausente permanece desconhecida e não passa em filtro mínimo de quantidade. Datas ausentes seguem a preferência existente. Recursos da 1.1.0 abaixo são preservados; suas validações live pertencem àquela execução.

Legenda: **Implementado** = código entregue e coberto por teste automatizado. Validações em aparelho real e no site da Meta estão em [TESTING.md](TESTING.md).

## Assistente da Biblioteca (novo)

| Recurso | Estado |
|---|---|
| Barra de ações por card (estilo TrendTrack): Salvar, **Página**, Copiar link, Compartilhar e selo "N DIAS · M ANÚNCIOS" | Implementado; validado live (Meta em português) |
| Botão **Página** no card: abre todos os anúncios ativos daquela Página (`view_all_page_id`, `active_status=active`). O Page ID é lido em "Ver detalhes do anúncio › Sobre o anunciante", nunca do link do perfil. Páginas que não mostram o ID ali (perfis com @usuário): o app digita o nome na busca da Meta e destaca o anunciante certo pelo @ do perfil; um toque seu abre a Página e o ID fica lembrado para os outros anúncios dela | Implementado; validado live nos dois caminhos (Sublime Concursos 106480812544708; Sólides Educação 266919370074481) |
| Salvar em 1 toque, sem formulário: Library ID, anunciante, data de início (origem "Lida do card"), status com data da verificação, texto/hook, link de vendas, variações, vídeo | Implementado; validado live |
| Comentário e tags opcionais pelo aviso "Comentar" | Implementado |
| Filtro de dias ativos (presets ou qualquer valor 0–365) aplicado nos próprios cards (oculta os demais, reversível) | Implementado; conferido card a card no live |
| Filtro de quantidade de anúncios ativos com o mesmo criativo ("N ads use this creative and text"; 2+, 3+, 5+, 10+, 20+ ou personalizado 1–1000) | Implementado; conferido card a card no live (12 de 30 com 2+) |
| Somente ativos é o padrão da busca (`active_status=active`); "Todos" fica na pílula do Explorar | Implementado |
| Contagem exibida pela Meta (~N) no cabeçalho e na barra; carregados / no filtro / ativos | Implementado; validado live |
| Contagem da Meta gravada no anunciante salvo, só se medida na mesma Página | Implementado; validado live (~180) |
| Auto-rolagem até achar mais N anúncios no filtro (10–100), com parar e detecção de fim | Implementado; validado live |
| Pré-filtros no Explorar: país, status, mídia (`media_type`), dias e quantidade de anúncios | Implementado |
| Desligável em Ajustes; lê só o texto visível dos cards, sem classes CSS, cookies ou rede | Implementado |

## Navegação na Biblioteca (WebView)

| Recurso | Estado |
|---|---|
| Site oficial da Biblioteca dentro do app, WebView criado uma vez e preservado entre abas | Implementado |
| Toolbar única de 6 ações: Voltar, Avançar, Atualizar, Voltar à pesquisa, Salvar, Mais | Implementado |
| Modo imersivo: oculta a navegação do app na Biblioteca, mantém toolbar compacta | Implementado |
| **Modo Feed**: só os anúncios, como um feed. Sem cabeçalho, barra de filtros, toolbar e navegação do app; um controle flutuante (Voltar, Filtros, Auto-rolar, Sair) que some ao rolar para baixo e volta ao subir. As barras fixas da Meta (logo, busca, Filtros) passam a rolar com a página, sem serem ocultadas | Implementado; validado live |
| Aviso quando o filtro local oculta todos os cards carregados, com "Procurar mais" e "Limpar" | Implementado |
| Recolher a toolbar em uma alça de 28 px (sem botões sobrepostos ao conteúdo da Meta) | Implementado |
| Alternar Página ↔ pesquisa pelo histórico do WebView (preserva rolagem, não recarrega) | Implementado |
| Atalho para a última Página visitada e para a última pesquisa | Implementado |
| Evita recarregar quando a URL pedida já está aberta | Implementado |
| Retomar a última URL ao reabrir o app (configurável) | Implementado |
| Modo padrão (cabeçalho com contexto), compacto (sem cabeçalho, toolbar 48 px), desktop (solicita layout desktop e recarrega) | Implementado; a Meta **ignorou** o pedido desktop no emulador |
| Aceita o redirecionamento oficial `web.facebook.com` (sem ele a 1.0.0 não exibia anúncios no emulador) | Implementado |
| Toque no nome do anunciante: explica que o ID do perfil pode não ser o Page ID; "Tentar como Page ID" com aviso ao salvar | Implementado |
| Teclado aberto oculta cabeçalho e toolbar | Implementado |
| Tamanho do texto do site (75–200%) no menu Mais e nos Ajustes; pinça | Implementado |
| Indicador de carregamento, aviso de lentidão (25 s), aviso de HTTP/página em branco | Implementado |
| Tela de erro com "Tentar novamente" e "Abrir no navegador" | Implementado |
| Fallback para navegador externo (Custom Tab / navegador padrão) | Implementado |
| Análise da área visível do WebView por ação explícita (OCR) | Implementado; depende de o WebView fornecer imagem |

## Salvos: Anunciantes e Outros (antes "Favoritos")

| Recurso | Estado |
|---|---|
| "Salvar anunciante" só com `view_all_page_id` válido na URL | Implementado (UI + repositório) |
| Sem Page ID: diálogo com Salvar como pesquisa / referência não identificada / informar Page ID / cancelar | Implementado |
| Page ID manual: só números, URL gerada, confirmação explícita, URL de origem preservada | Implementado |
| Migração de favoritos 1.0.0 salvos como anunciante sem Page ID → "Não identificadas" + marcador "Revisar" | Implementado |
| Correção manual ("Informar Page ID") mantendo nome, tags e notas | Implementado |
| Nicho, tags, notas, país, última visita, lista de observação | Implementado |
| Tela do anunciante: abrir na Meta, catalogar anúncio, "Anúncios salvos no AdsPocket", histórico de visitas | Implementado |
| Quantidade de anúncios | Mostra a contagem que a Meta exibe na Página, com data; o app não conta por conta própria |

## Salvos: Anúncios (antes "Mineração")

| Recurso | Estado |
|---|---|
| Formulário enxuto: nome, comentário, tags e situação; demais campos em "Mais detalhes" | Implementado |
| Cadastro completo opcional: oferta, anunciante, Page ID, ID do anúncio, links, nicho, categoria, preço/moeda/origem, data de início/origem, status, mídia, página de vendas, hook, headline, CTA, ângulo, variações, tags, notas, imagem, texto OCR, situação | Implementado |
| Filtro local de longevidade: sem filtro, 3, 7, 14, 21, 30, 60, 90, personalizado 0–365; padrão 14 | Implementado |
| Incluir/excluir registros sem data; contador "X de Y · filtro local"; limpar filtros | Implementado |
| Filtros por status, situação, mídia, anunciante, nicho, categoria e faixa de preço | Implementado |
| Faixa low ticket padrão R$ 9,90–97,00, moedas BRL/USD/EUR/GBP, faixas favoritas | Implementado |
| Origem do preço: confirmado, informado, sugerido por OCR, desconhecido | Implementado |
| Status ativo confirmado / inativo / desconhecido com data de verificação e alerta de verificação antiga (>7 dias) | Implementado |
| Ordenação: mais antigos, mais recentes, última verificação, preço, prioridade (score); valores ausentes sempre por último | Implementado |
| Revisão rápida: Descartar, Observar, Interessante, Salvar para modelar, nota, confirmar data, abrir anúncio/anunciante/página de vendas, desfazer | Implementado |
| Score de oportunidade 0–100 com cobertura e critérios pendentes | Implementado (opcional, informativo) |
| Comparador de duas referências com "Não informado" e alerta de coberturas diferentes | Implementado |

## OCR local

| Recurso | Estado |
|---|---|
| Google ML Kit (modelo latino embarcado, no aparelho, sem API paga) | Implementado |
| Imagem compartilhada pelo Android → "Analisar imagem" ou "Salvar imagem" | Implementado |
| Importar print pela Mineração ou pelo formulário | Implementado |
| Datas em português e inglês (por extenso, abreviadas, `dd/mm/aaaa`, ISO) | Implementado |
| Distinção "junto a frase de início" × "data sem contexto"; nenhuma data é aplicada sem confirmação | Implementado |
| Formato numérico ambíguo oferece as duas leituras | Implementado |
| Vários anúncios na imagem: sem pré-seleção, aviso e confirmação de associação | Implementado |
| Seleção de região da imagem para analisar um único anúncio | Implementado |
| Sugestão de preços reconhecidos (marcados "Sugerido por OCR") | Implementado |
| Guarda imagem, texto reconhecido, data confirmada e sua origem, data da captura e notas | Implementado |
| Valores de confiança | **Não exibidos** (o app não inventa confiança) |

## Dados

| Recurso | Estado |
|---|---|
| SQLite v3 com migrações aditivas a partir da v1/v2 | Implementado |
| Backup JSON v3 (favoritos, Mineração, histórico, ajustes, pesquisas); importa v1, v2 e v3; mescla sem sobrescrever | Implementado |
| Exportação CSV (Mineração e favoritos), `;`, UTF-8 com BOM, proteção contra fórmulas | Implementado |
| Backup ZIP com imagens | **Preparado**: política de validação de entradas (caminhos, duplicatas, tamanhos) testada; exportação/importação ZIP ainda não implementada |

## Distribuição

| Recurso | Estado |
|---|---|
| Workflow GitHub Actions: format, analyze, test, APK release, artefato, rascunho de release por tag `v*` | Criado; **não executado** no GitHub nesta sessão |
| Assinatura de produção por secrets; fallback para chave de desenvolvimento local | Implementado |

## Não implementado (por decisão ou limite externo)

- Reconstrução dos cards da Meta, scraping, APIs privadas, coleta de credenciais, contorno de CAPTCHA.
- Monitoramento em segundo plano de anunciantes, métricas de vendas.
- Extensões Copycat Ads / TrendTrack (nem simulação). Funções equivalentes independentes: catalogação, criativos, score, comparador.
- Download de mídia protegida ou interceptação de streams.
- Agrupamento automático de criativos semelhantes e análise estruturada de funil (P2).
