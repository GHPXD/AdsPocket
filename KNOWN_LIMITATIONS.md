# Limitações reais — 1.2.0

## Pesquisa 360° — 1.2.0

- Base importada da transcrição fornecida; PDFs originais não conferidos. Página exata desconhecida, intervalos preservados. Classificações e promessas dos materiais não são fatos estatísticos.
- Fontes externas são navegação assistida; nenhuma API de métricas conectada. Relatórios CSV de terceiros e radares permanecem no roadmap.
- Detectores analisam domínio e conteúdo fornecido localmente. Marcadores de tecnologia são prováveis; não há crawler ou confirmação de vendas.
- Dossiês/evidências são registros iniciais com vínculos e notas. Não há score multifonte, similaridade visual ou análise automática de funil.
- Preço/idioma/nicho são critérios auxiliares. Não são filtros oficiais da Meta.
- A suíte live da Meta da 1.1.0 é evidência histórica; não foi repetida nesta entrega. Validação física permanece pendente.

## Site externo (Meta)

- O AdsPocket é um navegador especializado. Resultados, anúncios exibidos, filtros aceitos, login, CAPTCHA e bloqueios de WebView pertencem à Meta e podem mudar sem aviso. A saída é abrir a mesma URL no navegador; o app nunca contorna restrições.
- Os parâmetros `active_status`, `ad_type`, `country`, `q`, `search_type`, `view_all_page_id` e `id` não são um contrato público estável. Testes cobrem a construção das URLs, não a aceitação contínua pelo site.
- O nome de um anunciante não identifica uma Página de forma única. A Página é escolhida nos controles da Meta; o app só reconhece o anunciante quando a URL contém `view_all_page_id`. Se a interface da Meta não expuser o ID na URL, use "Informar Page ID manualmente".
- **Verificação automática da Meta**: no emulador, a Meta responde primeiro com uma página de verificação que se recarrega e redireciona para `web.facebook.com`. Nesta versão o redirecionamento é aceito e os anúncios aparecem. Se a verificação não concluir em outro aparelho ou rede, o app mostra o aviso para continuar no navegador; ele não tenta contorná-la.
- **ID do perfil ≠ Page ID**: o nome do anunciante num card leva ao perfil do Facebook. No teste live, o perfil usava `61569677676829` e a Biblioteca, `468037109734919`. Por isso o app não trata o número do perfil como Page ID: oferece apenas "Tentar como Page ID", com aviso ao salvar. Os caminhos confiáveis são o botão **Página** do card (lê o ID em "Sobre o anunciante" nos detalhes do anúncio) ou escolher o anunciante na lista de anunciantes do campo de busca da Meta.
- Não há API comercial. Os contadores do app são locais ("salvos no AdsPocket") ou a contagem que a Meta exibe na tela, sempre identificada como "na Meta".

## Assistente da Biblioteca

- Funciona lendo o **texto visível** dos cards ("Library ID", "Started running on"/"Veiculação iniciada em", "Active", "Sponsored"). Não usa classes CSS nem APIs, mas depende das palavras que a Meta exibe em inglês ou português. Se a Meta mudar o layout ou os textos, os selos podem não aparecer; a navegação normal continua funcionando e o assistente pode ser desligado.
- A quantidade de anúncios é o "N ads use this creative and text" que a Meta imprime no card (anúncios ativos com o mesmo criativo e texto). Cards sem esse texto têm quantidade desconhecida e são excluídos quando um mínimo de quantidade está ativo. Não é o total de anúncios do anunciante; esse total aparece como "~N na Meta" na Página dele.
- Os filtros de dias e quantidade ocultam cards **já carregados**. Ele não muda a consulta feita à Meta. A contagem "~N na Meta" é o número exibido pela Meta para a busca/Página, não um cálculo do app.
- A auto-rolagem é feita na sua sessão, em ritmo de ~1 passo por segundo, e para no alvo, no fim da lista ou após 300 passos. Rolagem automática contínua pode ser interpretada pela Meta como uso automatizado; use com moderação.
- Validado no emulador Android 15 (WebView 124) com a Meta em inglês e em português (pt-BR). O botão **Página** e o modo Feed foram validados só em português; os rótulos em inglês ("See ad details", "About the advertiser") estão incluídos, mas não foram testados ao vivo.
- O botão **Página** abre "Ver detalhes do anúncio" e expande "Sobre o anunciante" na sua tela, por ~1–3 s, como você faria à mão; depois fecha. Algumas Páginas (perfis com @usuário) não mostram o ID ali: o app então digita o nome do anunciante na busca da Meta e destaca a opção cujo @ coincide com o link do perfil do card. **A Meta só aceita um toque real nessa lista**, então o último toque é seu; o app não simula toques. Se houver homônimos sem @ coincidente, nada é destacado e você escolhe. Nenhum ID é deduzido. O ID encontrado fica guardado na sessão para os outros anúncios do mesmo perfil.
- O modo Feed não esconde nada da Meta: as barras fixas (logo/menu, país, busca, Filtros) só deixam de ficar presas no topo e ficam a um gesto para cima. Os cards continuam no layout da Meta (vídeos verticais aparecem estreitos como no site).
- Preço não aparece no card da Meta; o anúncio salvo fica com preço "Desconhecido" até você informar.

## Navegador

- **Visual dos resultados**: os cards continuam sendo o layout web da Meta. A 1.1.0 aumenta a área útil (modos imersivo, compacto e Feed, toolbar única) mas não reconstrói nem reestiliza os cards. Nenhuma folha de estilo é injetada; o assistente só altera, de forma reversível, a visibilidade de cards filtrados e a fixação das barras no modo Feed.
- **Desktop**: o app solicita `preferredContentMode = DESKTOP` e recarrega. **No emulador (WebView 124) o layout não mudou**: viewport de 412 px antes e depois. Forçar exigiria trocar o User-Agent, o que o app não faz. Na prática, o modo desktop hoje equivale ao padrão nesse ambiente.
- **Histórico**: "Voltar à pesquisa" e o chip Página ↔ Pesquisa usam o histórico do WebView e preservam a rolagem na mesma sessão. Se a entrada não estiver mais no histórico, a pesquisa é recarregada (rolagem volta ao topo). Ao encerrar o processo, o app reabre a última URL, mas não a pilha de navegação nem a rolagem.
- **Captura da área visível**: depende de `takeScreenshot` do WebView. Se vier vazia, o app oferece importar um print. Não há captura contínua.
- Links `intent:`, `fb:`, `javascript:` e pop-ups sem URL não são executados. Login e destinos externos vão para o navegador; cookies do WebView e do navegador são independentes.
- Mídia em tela cheia e reprodução de vídeo dependem do site e do WebView do aparelho.
- **Download de criativo**: não há botão de download como o do TrendTrack. Baixar mídia exigiria capturar o arquivo do vídeo/imagem da Meta, o que a especificação não permite; use Copiar/Compartilhar o link do anúncio.

## Longevidade e status

- A idade é calculada a partir da data de início **que você informou ou confirmou** (manualmente ou via OCR). O app não busca datas na Meta.
- Idade não prova atividade contínua, desempenho ou lucratividade. "Ativo confirmado" vale para a data da verificação; após 7 dias o app sinaliza "verificação antiga". O status nunca é atualizado automaticamente.
- Os filtros de idade, preço e status são **locais** e se aplicam só às referências catalogadas na Mineração.
- "Hoje" usa o relógio e o fuso do aparelho; a diferença em dias é civil (sem efeito de horário de verão).

## OCR

- Reconhecimento pelo ML Kit com modelo latino embarcado; qualidade depende da nitidez do print. Não há valor de confiança exibido.
- O parser reconhece formatos comuns em português e inglês. Formatos fora desses padrões não são detectados; nesses casos informe a data manualmente.
- `05/10/2026` é lido como dia/mês e, por ser ambíguo, a leitura mês/dia também é oferecida; o usuário decide.
- A associação de uma data a um anúncio é sempre confirmada pelo usuário. Com vários anúncios no print, selecione a região ou confirme a associação.
- A seleção de região filtra as linhas reconhecidas pela posição; ela não recorta nem altera o arquivo salvo.

## Score e comparador

- O score é opcional e informativo. Só soma critérios com dados; a cobertura aparece ao lado. Score alto não significa vendas comprovadas. Comparações com coberturas diferentes recebem alerta.
- "Diversidade de criativos" usa a quantidade de variações que você viu e informou, não uma contagem da Meta.

## Arquivos e backup

- JSON v3 inclui favoritos, Mineração, histórico, ajustes e pesquisas; **não inclui imagens** (o campo da imagem é removido). Importa backups v1, v2 e v3, valida tudo antes e nunca sobrescreve registros existentes.
- Backup ZIP com imagens **não está implementado**. Foi preparada e testada a política de validação de entradas (`ArchivePolicy`); a exportação/importação ZIP fica para uma próxima versão.
- CSV usa `;` e UTF-8 com BOM para abrir em planilhas em português. Valores iniciados por `= + - @` recebem apóstrofo.
- Imagens: PNG/JPEG/WebP, até 15 MB e 40 megapixels.

## Distribuição

- O workflow existente foi preservado e compila o APK em pushes na `main`. Os resultados remotos devem ser conferidos no GitHub Actions; a validação local não confirma aprovação do CI.
- Sem os secrets de assinatura, o CI assina com a chave de debug do runner, diferente da chave local. Instalar esse APK sobre um build local exige desinstalar antes (perde os dados locais). Para atualizações contínuas, configure `ADSPOCKET_KEYSTORE_BASE64`, `ADSPOCKET_KEYSTORE_PASSWORD`, `ADSPOCKET_KEY_ALIAS` e `ADSPOCKET_KEY_PASSWORD`.
- O APK local da 1.2.0 é assinado com a mesma chave de desenvolvimento da 1.0.0 e atualiza sem desinstalar. Trocar depois para uma chave de produção exigirá uma desinstalação única.
- Validação em aparelho físico (Galaxy S23 Ultra) pendente: nenhum aparelho físico estava conectado. O emulador x86_64 com GPU por software não representa desempenho real.
- O ML Kit aumentou o APK release de 54 MB (1.0.0) para 87 MB e acrescentou a permissão `ACCESS_NETWORK_STATE` (dependência do ML Kit; o app não a usa para coletar dados).
- O OCR com ML Kit real ainda não foi exercitado com um print real no aparelho; o parser e a tela foram testados no host com um motor de OCR substituto.
