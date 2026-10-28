# Validação

Data de referência: 28/10/2026 (America/Sao_Paulo).

## Ambiente

Flutter 3.47.2 stable, Dart 3.13.2, Windows 11. Android SDK instalado, API 35 disponível no emulador Pixel 8 `WeSyncAd` (x86_64). Java 21 selecionado para Gradle. O `flutter doctor -v` alertou que não conseguiu consultar o status de licenças, apesar dos componentes de SDK presentes. O resultado efetivo de compilação é o critério de disponibilidade.

O primeiro build com o template AGP 9.1 falhou no plugin estável `flutter_inappwebview_android`, por remoção do proguard-android.txt. O projeto foi ajustado para AGP 8.13.2, Gradle 8.14.3 e Kotlin 2.2.20. Não foram modificados arquivos no cache de dependências.

## Testes automatizados locais

`flutter test`: **33 testes aprovados** após correções. Cobertura funcional:

- Construção de palavras-chave, Page ID, status e país; encoding de acentos e caracteres reservados.
- Preservação do link original e identificação de Página; deduplicação por URL canônica.
- Rejeição de HTTP, JavaScript, credenciais na URL, domínios semelhantes, portas arbitrárias, IDs inválidos e parâmetros ID duplicados.
- Extração limitada de links compartilhados válidos; textos malformados e limites de tamanho.
- SQLite real em memória e em arquivo: reinício, ID estável, deduplicação, edição e exclusão.
- Consultas parametrizadas com entrada contendo SQL; limpar histórico sem apagar favoritos.
- Backup round trip, versão incompatível, esquema inválido, caminhos locais, links inseguros e configurações fora dos limites.
- Importação sem sobrescrita e contagem de novos registros.
- Configurações e última Página persistidas; pesquisa real registrada pelo controller.
- Widgets de Explorar, Favoritos, Configurações e Histórico; alternância de tema, navegação e tela estreita com texto ampliado.

O teste de persistência usa SQLite via FFI no host; os testes de widget usam o fallback visual porque não existe WebView Android no processo de teste local. O teste Android verifica o plugin real separadamente. Nenhum teste usa cards falsos de anúncios.

## Comandos reproduzíveis

```powershell
flutter pub get
dart format .
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d emulator-5554
```

## Android

O teste `integration_test/app_test.dart` usa banco separado `adspocket.integration.db`, inicia a UI real, submete `planilha`, verifica a criação de WebView e sua preservação entre abas, salva uma referência de Página, reabre o banco, confere histórico e preferências, reabre o favorito e chama o navegador externo. O ID explícito de teste não é incluído no banco de produção nem nos favoritos iniciais. A disponibilidade dos anúncios dessa Página é uma verificação independente.

Screenshots, quando capturadas pelo driver, ficam em `docs/screenshots/`.

## Resultado Android executado

O fluxo de `flutter drive` terminou com **All tests passed**. Uma segunda execução conectada ao app iniciado por `ACTION_SEND` também terminou com **All tests passed** e registrou `ADSPOCKET_COLD_SHARE_RECEIVED=true`.

Comprovado no emulador API 35:

- Inicialização nativa e submissão de `planilha` pela tela Explorar.
- Criação real do WebView; URL na Biblioteca oficial, título **Ad Library**, sem erro HTTP/rede sinalizado nessa etapa.
- Mesma instância do controller após alternar Explorar/Biblioteca.
- Abertura de referência explícita de Página e salvamento pelo diálogo **Salvar anunciante**.
- Histórico e favorito presentes após fechar/reabrir o banco e recriar o aplicativo Flutter; preferência de tema preservada. Isso não equivale a restaurar toda a pilha WebView após encerramento do processo Android.
- Reabertura do favorito salvo com `view_all_page_id` e atualização da última visita.
- Tema claro aplicado de verdade.
- Entrega de intents de texto HTTPS com o app aberto e após `KEYCODE_HOME`, com diálogo de importação e abertura do link recebido.
- Início do processo por compartilhamento a frio, com diálogo confirmado e captura `00-compartilhamento-inicial.png`.
- Abertura externa confirmada pelo Android no pacote `com.android.chrome`. O Chrome do emulador abriu sua tela de primeiro uso; a configuração inicial dele não foi concluída. Foi necessário trazer o AdsPocket de volta ao primeiro plano para o runner concluir sua última renderização.

As entregas foram geradas com `adb shell am start ... -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT <link>`, exercitando os intents reais. O seletor de compartilhamento de cada outro aplicativo não foi percorrido manualmente.

Capturas verificadas: `docs/screenshots/01-explorar.png` e `00-compartilhamento-inicial.png`. A captura da superfície híbrida do WebView ficou aguardando uma imagem no runner e foi retirada do caminho funcional do teste. A primeira tentativa também confirmou que o controller deve ser aguardado de forma assíncrona. A espera e o fechamento dos diálogos foram corrigidos; as execuções finais passaram.

O teste não afirma que havia anúncios ativos para a Página de referência, nem confirma a seleção de uma Página pelos controles internos do site. Verificar título/URL não comprova que os cards reais de resultados foram apresentados. Nenhum card fictício foi acrescentado.

## Análise e builds

`flutter analyze`: **No issues found**, após o ajuste final do navegador. `dart format .`: executado. Os builds de produção usam explicitamente `--target=lib/main.dart`, para que os APKs de entrega não iniciem o runner de integração.

A primeira tentativa release recebeu um registrador gerado com o plugin de integração, enquanto outro comando Flutter preparava ferramentas. Os comandos finais de teste, debug e release são executados sequencialmente. Não execute análise/pub get durante um build Android: esses comandos podem regenerar o mesmo arquivo `GeneratedPluginRegistrant.java`.

Builds finais **aprovados** com `--target=lib/main.dart`:

| Artefato | Bytes | SHA-256 |
|---|---:|---|
| `dist/AdsPocket-1.0.0.apk` (release) | 56.751.565 | `FEEB6099CDBDD3B0FB0C4AAE88E98CECC58E22A37A9A1C6DF943BD8CF6F16A42` |
| `dist/AdsPocket-1.0.0-debug.apk` | 211.986.366 | `951B808F1C73AF653B06CF27AB76A94FD914E4AC78DFD464D70E46B0C615F2AC` |

`apksigner verify --verbose --print-certs` aprovou ambos (assinatura v2). Release utiliza assinatura real de desenvolvimento para uso pessoal, descrita no README; nenhuma chave privada foi incluída. Metadados conferidos com `aapt dump badging`: versão 1.0.0+1, minSdk 24, compileSdk/targetSdk 36, ABIs arm64-v8a, armeabi-v7a e x86_64. A permissão de plataforma é INTERNET; há ainda uma permissão privada de receiver gerada pelo AndroidX, sem permissão de armazenamento/câmera/microfone.

O APK release de entrega foi instalado em estado limpo no emulador e iniciado pela `MainActivity`: Android retornou `Status: ok`, `LaunchState: COLD`, e a tela Explorar com tema escuro foi capturada e inspecionada em `docs/screenshots/02-release.png`. O teste de inicialização usa o ponto de entrada real `lib/main.dart`, incluindo sua abertura de banco e preferências. A suíte local final repetiu **33 testes aprovados**.

## Verificações ainda pendentes

- Selecionar anunciante dentro do site, verificar seus cards de anúncios reais e confirmar todos os países/status no serviço externo.
- Botão físico/preditivo voltar, rolagem e retorno à posição em aparelho físico.
- Reprodução de vídeos/tela cheia, pinça, orientação e pop-ups de login nos diferentes WebViews.
- Perda/retorno de conexão em dispositivo; os estados de erro estão implementados, mas não houve ensaio de rede controlado.
- Uso dos seletores Android SAF para exportar/importar backup e importar imagens, além de compartilhamento de imagens por outros apps. JSON e persistência foram testados automaticamente no host.
- Fluxo de envio pela folha nativa de share_plus e seleção manual do destinatário.
- Instalação e desempenho no Galaxy S23 Ultra.

Esses itens não são declarados aprovados por compilação, testes de widget ou pela abertura da URL oficial.

