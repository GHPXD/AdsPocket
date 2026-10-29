import json,re,unicodedata
from pathlib import Path
import sys
source=Path(sys.argv[1]) if len(sys.argv)>1 else Path('assets/knowledge/transcription.txt')
src=source.read_text(encoding='utf-8-sig')
Path('assets/knowledge/transcription.txt').write_text(src,encoding='utf-8')
def norm(s): return ' '.join(''.join(c for c in unicodedata.normalize('NFKD',s.casefold()) if not unicodedata.combining(c)).split())
names=['Ganhar Dinheiro','Saúde e Beleza','Relacionamentos','Desenvolvimento Pessoal','Finanças Pessoais','Educação Profissional','Design e Criatividade','Espiritualidade e Bem-estar']
subs=[['Renda extra', 'Trabalhar de casa', 'Negócios digitais', 'E-commerce', 'Empreendedorismo', 'Educação financeira', 'Capacitação para geração de renda'], ['Emagrecimento', 'Diabetes', 'Próstata', 'Fungos e micoses', 'Estrias', 'Rejuvenescimento', 'Disfunção erétil', 'Dores nas articulações', 'Dores nas costas'], ['Conquista', 'Reconquista', 'Relacionamentos', 'Suspeitas de infidelidade'], ['Produtividade', 'Procrastinação', 'Hábitos', 'Foco', 'Gestão de tempo', 'Motivação', 'Metas', 'Inteligência emocional', 'Organização', 'Comunicação'], ['Organização financeira', 'Controle de gastos', 'Orçamento familiar', 'Dívidas', 'Planejamento', 'Poupança', 'Investimentos para iniciantes', 'Reserva de emergência', 'Planilhas financeiras'], ['Currículo', 'Entrevistas', 'Qualificação', 'Certificações', 'Habilidades digitais', 'Carreira', 'LinkedIn', 'Ferramentas profissionais', 'Desenvolvimento de competências'], ['Templates', 'Canva', 'Identidade visual', 'Design para redes sociais', 'Pacotes gráficos', 'Recursos editáveis', 'Design profissional', 'Materiais prontos'], ['Meditação', 'Bem-estar', 'Autoconhecimento', 'Rotina', 'Respiração', 'Equilíbrio emocional', 'Práticas de reflexão']]
niches=[dict(id=str(i+1),name=n,subniches=subs[i],sourceId='transcription-doc1-and-master',classification='Atributo do material original; não é evidência estatística') for i,n in enumerate(names)]
terms=[]; seen=set(); duplicates=0; niche='';sub='';part=0;doc='doc1';category='assunto';pages='1–6'
for line in src.splitlines():
 line=line.strip()
 if line.startswith('Documento 2'): doc='doc2';category='formato';niche='';sub='';pages='1–2'
 if line.startswith('Parte '):
  part=int(re.search(r'Parte (\d)',line)[1]);pages='1–6' if part<3 else '7–13' if part==3 else '13–15'
 if doc=='doc1':
  m=re.match(r'^([1-8])[. —–-]+(.+)$',line)
  if m and part in [2,3]: niche=names[int(m[1])-1];sub=''
  m=re.match(r'^[a-i]\) (.+)$',line)
  if m: sub=m[1]
 if doc=='doc2' and line.startswith('Para encontrar'): category='comercial'
 if doc=='doc2' and line.startswith('Palavras que revelam'): category='atualização histórica'
 if not line.startswith('- ') or (doc=='doc1' and part not in [2,3]): continue
 value=line[2:].strip().strip('"')
 key=(doc,norm(value),niche,sub)
 if key in seen:
  duplicates+=1
  continue
 seen.add(key)
 terms.append(dict(text=value,normalized=norm(value),niche=niche,subniche=sub,sourceId=doc,pageRange=pages,page=None,category=category if doc=='doc2' else 'assunto',historical=bool(re.search(r'202[45]',value)),note='Expressão de pesquisa do material, não comprovação de eficácia ou resultado.',importedAt='2026-10-29'))
formats=['Planilha pronta','Template','Checklist pronto','E-book','Documento digital','Pack','Guia prático','Material para imprimir','Material revisado','Curso rápido','Ferramenta digital']
for t in ['Kit digital','Kit profissional','Pack premium','Ferramenta pronta','Material para imprimir','Guia prático','Manual digital','Biblioteca de modelos','Controle em Excel','Arquivo para download','Planilha automatizada','PDF preenchível','Arquivo personalizável','Material para profissionais']:
 terms.append(dict(text=t,normalized=norm(t),niche='',subniche='',sourceId='system-expansion',pageRange=None,page=None,category='expansão do sistema',historical=False,note='Ampliação do sistema; não extraído dos PDFs.',importedAt='2026-10-29'))
for i,n in enumerate(niches):
 n['materialClassification']=['Altamente escalável',None,None,'EXTREMAMENTE ESCALÁVEL','EXTREMAMENTE ESCALÁVEL','MÉDIA A ALTA','MÉDIA','MÉDIA A ALTA'][i]
 n['classificationSource']='doc1; classificação do autor, não verificação estatística'
data=dict(importReport=dict(duplicateOccurrencesSkipped=duplicates,referenceTerms=len(terms)-14,systemExpansionTerms=14,excluded='Texto explicativo e instruções gerais preservados na transcrição; não convertidos em palavras-chave.',riskPolicy='Alegações de cura, renda ou vigilância são assuntos do material, não recomendações ou evidência de eficácia.'),version=1,importedAt='2026-10-29',sourceStatus='Transcrição integral fornecida pelo usuário processada; PDFs originais não disponibilizados. Páginas conhecidas apenas por intervalos.',sources=[dict(id='doc1',title='Nichos e subnichos',originalFilename='Nichos e subnichos (1).pdf',pages=15),dict(id='doc2',title='Mineração',guideTitle='MINERAÇÃO LOW TICKET',originalFilename='1781632755730-37pp4c6jk1v (1).pdf',pages=2)],niches=niches,terms=terms,formats=formats,commercial=['Pronto para uso','Entrega imediata','R$ 9,90','R$ 12,90'],strategySource='Curadoria do sistema a partir dos formatos da transcrição; combinações são sugestões, não trechos extraídos.',formatVariants={'Planilha pronta':['Excel pronto','Planilha editável'],'Template':['Canva editável','Modelo pronto'],'Documento digital':['Documentos prontos','Word editável'],'Checklist pronto':['Lista pronta'],'E-book':['Em PDF','Guia prático']},priceRanges=['Até R$ 19,90','Até R$ 47','Até R$ 97'],deliveryTerms=['Entrega imediata','Download imediato'],updateTerms=['Versão atualizada','Material revisado'],presets=[dict(name=n,format=f) for n,f in [('Planilhas low ticket','Planilha pronta'),('E-books baratos','E-book'),('Packs de templates','Template'),('Documentos profissionais','Documento digital'),('Checklists prontos','Checklist pronto'),('Materiais revisados','Material revisado'),('Cursos rápidos','Curso rápido'),('Ferramentas digitais','Ferramenta digital')]]+[dict(name='Ofertas com 30+ dias',format='Planilha pronta',minDays='30'),dict(name='Criativos com múltiplas variações',format='Template',minAds='2')])
Path('assets/knowledge/catalog.v1.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
icons={'pocket':'M5 4H19V15Q12 24 5 15ZM9 10L12 13L15 10','explore':'M12 3A9 9 0 1 0 12 21A9 9 0 1 0 12 3M15.5 8.5L13.4 13.4L8.5 15.5L10.6 10.6Z','library':'M5 4H19Q21 4 21 6V18Q21 20 19 20H5Q3 20 3 18V6Q3 4 5 4ZM3 9H21M8 9V20M11 13H17M11 16H15','grid':'M3 3H10V10H3ZM14 3H21V10H14ZM3 14H10V21H3ZM14 14H21V21H14Z','scan':'M3 8V3H8M16 3H21V8M21 16V21H16M8 21H3V16M7 9H17M5 12H19M7 15H14','source':'M12 3V7M5 16L10 7M14 7L19 16M8 18H16','document':'M5 3H19V21H5ZM9 8H15M9 12H15M9 16H12'}
for name,d in icons.items(): Path('assets/icons/'+name+'.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#8B8DF8" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round"><path d="{d}"/></svg>',encoding='utf-8')
print('Imported',len(terms),'terms;',len(niches),'niches; original SVG assets generated.')
