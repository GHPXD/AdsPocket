# Limitações reais

## Site externo

O AdsPocket é um navegador especializado; resultados, disponibilidade de anúncios e políticas de acesso pertencem à Meta. O site pode exigir login, CAPTCHA, bloquear WebViews ou limitar regiões. A solução oferecida é abrir a mesma URL em uma aba do navegador. O app nunca contorna essas restrições.

O formato `active_status`, `ad_type`, `country`, `q`, `search_type` e `view_all_page_id` é construído centralmente. Não é contrato público estável. Os formatos são cobertos por testes de construção, mas isso não comprova que cada filtro continuará aceito pelo site. Links recebidos são preservados integralmente, inclusive parâmetros desconhecidos e fragmento. A chave de deduplicação é separada e não substitui o link original.

Nesta execução, a ferramenta de leitura web retornou falha de cache para a pesquisa oficial e HTTP 403 para a página de documentação da API. A validação Android é registrada separadamente em TESTING.md. Não há API geral de anúncios comerciais brasileiros integrada. O projeto não solicita token de API nem promete obter dados comerciais indisponíveis.

## Navegador

- A busca por nome abre uma pesquisa oficial e orienta a seleção da Página nos controles da Meta. Não resolve nomes em IDs automaticamente.
- A seleção dentro do site depende de a Meta permitir sua interface no WebView. O app identifica Páginas pela URL; se a navegação não expuser o ID, salve o link com nome manual.
- Login e destinos externos usam o navegador; os estados de cookies dos dois ambientes podem ser diferentes. Não há sincronização nem extração desses cookies.
- Links `intent:`, `fb:`, `javascript:` e outros esquemas não são executados. Para prosseguir, abra a Biblioteca no navegador compatível.
- Pop-ups com URL HTTPS explícita são tratados; pop-ups sem destino ou baseados em `about:blank` pedem uso do navegador.
- O modo desktop usa a preferência nativa do WebView. A Meta pode manter layout mobile. Não há troca manual de User-Agent para superar bloqueios.
- O zoom de texto pode afetar o layout do site. A pinça depende de o site/WebView permitir. Não há personalização CSS ou reconstrução de cards.
- Voltar normal preserva o histórico do WebView. Alternar abas mantém a mesma instância. Fechar o processo não restaura toda a pilha/rolagem; pesquisas, favoritos e última Página são persistidos.
- Os avisos de carregamento lento e rede não detectam semanticamente todo CAPTCHA ou aviso de login. O botão externo fica disponível.
- Mídia em tela cheia depende do site e do plugin. Não há garantia de reprodução em todos os formatos.

## Arquivos e backup

- Downloads iniciados no site abrem a origem no navegador; não há gerenciador de downloads próprio nem extração de mídia protegida. Se indisponível, salve o link do anúncio.
- Imagens importadas: PNG/JPEG/WebP, até 15 MB e 40 megapixels. Outros formatos são rejeitados. Não há edição, OCR ou download automático.
- Remover uma referência de imagem ou cancelar seu cadastro remove o arquivo privado correspondente. Um encerramento abrupto durante a importação ainda pode deixar arquivo sem referência; limpar armazenamento/desinstalar remove a área privada.
- JSON versão 1: até 5 MB, até 10.000 referências e 500 pesquisas. Imagens e cookies não fazem parte dele. O arquivo é legível e inclui notas pessoais; o app o grava apenas no destino escolhido pelo usuário.
- A importação valida todos os registros e preserva conflitos de ID/URL. Não há opção de sobrescrita automática. Configurações só são aplicadas com escolha explícita no diálogo.
- Android pode encerrar o processo enquanto o seletor de arquivos está aberto. Nesse caso, repita a operação. Não há serviço permanente em segundo plano.
- Cache de navegação é independente de SQLite/shared_preferences; limpar cache não limpa cookies. A exclusão integral é oferecida pelo Android em Limpar armazenamento.

## Distribuição

Somente Android é alvo de produção. API mínima 24. O APK release para uso pessoal utiliza assinatura de desenvolvimento real, conforme README; publicação exige sua própria chave de produção. Não há chave falsa ou segredo incluído. Validação no S23 Ultra e em aparelho físico está pendente até existir dispositivo disponível.

Flutter 3.47.2 ainda aceita a cadeia Android fixada, mas emite avisos sobre a retirada futura do suporte a AGP 8 / Gradle 8 / Kotlin 2.2. Uma atualização futura do Flutter deve ser acompanhada da migração do WebView e da cadeia de compilação. Não foi usado bypass da validação de dependências.

A captura de tela do runner de integração funciona antes da montagem do WebView, mas ficou aguardando uma imagem ao capturar sua superfície nativa híbrida neste emulador. O teste funcional não depende dessa captura. O emulador x86_64 usa GPU por software; seus tempos de quadros em debug não são uma avaliação de desempenho do S23 Ultra.

