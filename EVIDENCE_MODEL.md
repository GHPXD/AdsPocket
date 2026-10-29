# Evidências e dossiês — 1.2.0

`ResearchRecord`: ID local, nome, tipo (pacote/dossiê/evidência), data de criação e dados versionados pelo backup. Evidências e dossiês têm observações, URL HTTPS opcional, data de coleta, confiança, IDs de anúncios relacionados e IDs de evidências. Dossiês são uma estrutura inicial para organizar referências; não geram análises automáticas.

Confiança da origem: informado pelo usuário, observado em fonte pública, estimativa ou desconhecido. O resultado técnico de um detector mantém também `detectionConfidence`, versão da regra e a referência que sustenta a regra. Conteúdo colado pelo usuário continua marcado como informado pelo usuário, mesmo que o domínio seja conhecido.

SQLite v3 adiciona somente a tabela `research`; as tabelas anteriores são preservadas. Backup JSON v3 inclui pesquisas, aceita v1/v2, valida antes da transação e importa sem sobrescrever IDs existentes. Excluir um registro não exclui anúncios; referências a IDs ausentes são omitidas da exibição. Ao compartilhar um dossiê isolado, os IDs relacionados são referências locais: os anúncios/evidências devem existir no destino ou ser transferidos pelo backup completo.

Limites: nomes de 200 caracteres, notas de 10 mil, listas de até 500 itens, profundidade 12, registro de até 500 mil caracteres e backup de até 5 MB. Nenhum HTML importado é executado. Imagens e anexos de evidência dedicados ficam para evolução; OCR e imagens dos anúncios existentes continuam disponíveis.
