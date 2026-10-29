# Detecção local — regra 2026-10-29.1

Entrada: URL HTTPS e, opcionalmente, HTML/texto público fornecido pelo usuário. O detector não faz requisições, executa HTML ou intercepta tráfego. Cada evidência salva registra tecnologia, página, sinal observado, confiança, data, regra e referência técnica.

| Evidência | Resultado |
|---|---|
| Host exato pay.kiwify.com.br / pay.cakto.com.br / pay.hotmart.com | Checkout confirmado pelo domínio; não confirma produto ou vendas |
| Marcadores públicos WordPress, Elementor, Google Tag Manager, Google tag, Meta Pixel, Shopify, Typebot, UTMify | Provável: o trecho fornecido pode estar desatualizado ou inativo |
| Nenhuma regra encontra evidência | Desconhecido |

Domínios parecidos não são aceitos. Google tag pode atender Analytics e Ads; o marcador sozinho não distingue os produtos. Meta Pixel exige domínio connect.facebook.net e fbevents.js juntos. HTML é limitado a 500 mil caracteres.

Referências verificadas em 29/10/2026: [Kiwify](https://ajuda.kiwify.com.br/pt-br/article/como-preencher-os-campos-do-checkout-pela-url-de7ezo/), [Cakto](https://cakto.com.br/checkout), [Hotmart](https://pay.hotmart.com/), [Google tag](https://developers.google.com/tag-platform/gtagjs), [Tag Manager](https://developers.google.com/tag-platform/tag-manager/web), [UTMify: script público](https://cdn.utmify.com.br/scripts/utms/latest.js). Referências adicionais de cada regra ficam no código e na evidência. A presença de um marcador não demonstra funcionamento atual ou rastreamento efetivo.
