# Funcionalidades implementadas

| Área | Implementação |
|---|---|
| Explorar | Palavra-chave, nome de anunciante, link direto e Page ID; país/status; encoding; limpar campo; atalhos editáveis; histórico recente e última Página |
| Biblioteca | Site oficial, controles voltar/avançar/atualizar, progresso, topo, copiar, compartilhar, salvar anunciante/pesquisa/anúncio, voltar à busca inicial |
| Falhas | Erro principal de rede/HTTP, aviso após 25 segundos, recarregar e abrir navegador; navegação HTTPS externa confirmada |
| Visualização | Padrão, compacto, desktop solicitado ao WebView, recolher ferramentas, tela cheia e mídia suportada pelo site |
| Favoritos | Categorias, nome, país, data, Page ID conhecido, tags, notas, categoria da oferta, busca e ordenação por nome/visita/adição |
| Histórico | SQLite real, até 500 pesquisas, deduplicação, repetir com um toque, salvar favorito, buscar, excluir ou limpar |
| Compartilhamento | Enviar URL via share_plus; receber texto e links via intents Android, diálogo abrir/salvar/copiar/cancelar |
| Imagens | Escolher ou receber PNG/JPEG/WebP, validar limites e cabeçalhos, copiar para área privada, visualizar com zoom |
| Lojas e ofertas | Referências HTTPS externas com categoria, tags, notas e data; abertura no navegador |
| Preferências | Tema escuro/claro/sistema, país, status, modo, abertura externa e tamanho do texto do site |
| Dados | Exportar JSON com seletor Android; importar com validação, prévia e escolha sobre configurações; mesclar sem sobrescrever |
| Sobre | Informação independente, privacidade local, versão, licenças e link oficial |

Uma referência salva não equivale a uma mídia baixada. Os números da tela Favoritos contam apenas registros locais, nunca anúncios encontrados na Meta. A contagem exibida no site oficial permanece intacta.

Recursos que dependem da Meta: seleção da Página pelo nome, resultados e filtros efetivamente disponíveis, login, funcionamento de vídeos, pop-ups e layout desktop. O fallback externo está disponível mesmo sem carregamento do site. O fluxo por nome não promete autocomplete nativo nem consulta de ID por API.

Downloads explícitos oferecidos pelo site são encaminhados à origem no navegador. Não há gerenciador próprio de downloads, busca de streams, cópia de cookies, extensão Copycat/TrendTrack, OCR, métricas comerciais ou coleta de lojas. Esses itens não são apresentados como implementados.
