# Entrega local 1.2.0+3 — 29/10/2026

APK: `dist/AdsPocket-1.2.0.apk` (92.075.948 bytes). SHA-256: `8426cea04d64e6e0ccd4606a6a556977d6d3ad8926c08da526f9991e736a6f9c`. O APK e os relatórios de assinatura/hash são ignorados pelo Git.

Release compilado com entrada `lib/main.dart`, Android mínimo API 24, alvo API 36 e ABIs arm64-v8a/armeabi-v7a/x86_64. Assinatura local de desenvolvimento preservada, certificado igual ao APK 1.1.0. Instalação por cima e abertura conferidas no emulador Android 15.

Validação: formato sem alterações, análise sem problemas, 118 testes host aprovados e suíte Android de pesquisa/assistente aprovada. Migração v2→v3 e backups antigos cobertos por testes. Veja [Validação](../TESTING.md), [Changelog](../CHANGELOG.md) e [Limitações](../KNOWN_LIMITATIONS.md).

A base usa a transcrição fornecida; conferência integral dos PDFs originais permanece pendente. Provedores externos operam por navegação assistida. A suíte live da Meta não foi repetida; aparelho físico ainda não testado. Fases 2/3 permanecem no roadmap.

O workflow existente foi preservado e compila o APK em pushes na `main`. Nenhuma tag ou publicação de release foi executada nesta entrega; o APK validado está disponível localmente em `dist/`.
