-- ════════════════════════════════════════════════════════════════════
-- LIMPEZA DE DADOS DE TESTE — Diagnóstika Engenharia
-- Preparado em 31/05/2026
--
-- INSTRUÇÕES:
-- 1. Rode primeiro o BLOCO 1 (só SELECT) e revise o que aparece.
-- 2. Se estiver correto, rode o BLOCO 2 (DELETE/UPDATE).
-- 3. Confirme em cada portal que só dados reais aparecem.
-- ════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════
-- BLOCO 1 — DIAGNÓSTICO (só leitura, rode primeiro)
-- ════════════════════════════════════════════════════════════════════

-- 1A. Contar registros por tabela e condomínio
SELECT 'demandas' as tabela, condo_id, COUNT(*) as total
FROM demandas WHERE deletada_em IS NULL
GROUP BY condo_id

UNION ALL

SELECT 'portaria_eventos', condo_id, COUNT(*)
FROM portaria_eventos
GROUP BY condo_id

UNION ALL

SELECT 'manutencoes', condo_id, COUNT(*)
FROM manutencoes WHERE deletada_em IS NULL
GROUP BY condo_id

UNION ALL

SELECT 'visitas', condo_id, COUNT(*)
FROM visitas
GROUP BY condo_id

ORDER BY tabela, condo_id;

-- ─────────────────────────────────────────────────────────────────
-- 1B. Demandas identificadas como teste
SELECT
  id,
  condo_id,
  protocolo,
  titulo,
  morador_nome,
  morador_apto,
  origem,
  created_at::date as data,
  CASE
    WHEN condo_id = 'condominio-teste'                              THEN 'sandbox'
    WHEN user_id = 'f3be2359-d8e7-4574-b42e-4bd2de90b3bb'         THEN 'conta E2E'
    WHEN morador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%visitante%','%e2e%','%fictício%','%ficticio%']) THEN 'nome fake'
    WHEN titulo      ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])                            THEN 'título fake'
    ELSE 'verificar'
  END as motivo
FROM demandas
WHERE deletada_em IS NULL
  AND (
    condo_id = 'condominio-teste'
    OR user_id = 'f3be2359-d8e7-4574-b42e-4bd2de90b3bb'
    OR morador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%visitante%','%e2e%','%fictício%','%ficticio%'])
    OR titulo       ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])
  )
ORDER BY condo_id, created_at;

-- ─────────────────────────────────────────────────────────────────
-- 1C. Eventos de portaria identificados como teste
SELECT
  id,
  condo_id,
  porteiro,
  prestador_nome,
  tipo_evento,
  hora::date as data,
  CASE
    WHEN condo_id = 'condominio-teste'                                             THEN 'sandbox'
    WHEN porteiro      ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])   THEN 'porteiro fake'
    WHEN prestador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])  THEN 'prestador fake'
    ELSE 'verificar'
  END as motivo
FROM portaria_eventos
WHERE
  condo_id = 'condominio-teste'
  OR porteiro       ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])
  OR prestador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])
ORDER BY condo_id, hora;

-- ─────────────────────────────────────────────────────────────────
-- 1D. Manutenções identificadas como teste
SELECT
  id,
  condo_id,
  protocolo,
  titulo,
  created_at::date as data
FROM manutencoes
WHERE deletada_em IS NULL
  AND (
    condo_id = 'condominio-teste'
    OR titulo ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%','%exemplo%'])
  )
ORDER BY condo_id, created_at;


-- ════════════════════════════════════════════════════════════════════
-- BLOCO 2 — LIMPEZA (só rode após confirmar o BLOCO 1)
-- ════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────
-- 2A. Soft-delete demandas de teste (não apaga fisicamente — mantém auditoria)
UPDATE demandas SET
  deletada_em       = NOW(),
  deletada_por_nome = 'Rogério — limpeza pré-divulgação',
  deletada_motivo   = 'Dado de teste removido antes do lançamento oficial',
  updated_at        = NOW()
WHERE deletada_em IS NULL
  AND (
    condo_id = 'condominio-teste'
    OR user_id = 'f3be2359-d8e7-4574-b42e-4bd2de90b3bb'
    OR morador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%visitante%','%e2e%','%fictício%','%ficticio%'])
    OR titulo       ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])
  );

-- Quantas demandas foram ocultadas:
SELECT COUNT(*) as demandas_removidas
FROM demandas
WHERE deletada_motivo = 'Dado de teste removido antes do lançamento oficial';

-- ─────────────────────────────────────────────────────────────────
-- 2B. Apaga eventos de portaria de teste (portaria_eventos não tem soft-delete)
DELETE FROM portaria_eventos
WHERE
  condo_id = 'condominio-teste'
  OR porteiro       ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%'])
  OR prestador_nome ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%']);

-- ─────────────────────────────────────────────────────────────────
-- 2C. Soft-delete manutenções de teste
UPDATE manutencoes SET
  deletada_em       = NOW(),
  deletada_por_nome = 'Rogério — limpeza pré-divulgação',
  deletada_motivo   = 'Dado de teste removido antes do lançamento oficial',
  updated_at        = NOW()
WHERE deletada_em IS NULL
  AND (
    condo_id = 'condominio-teste'
    OR titulo ILIKE ANY(ARRAY['%teste%','%demo%','%e2e%','%fictício%','%exemplo%'])
  );

-- ─────────────────────────────────────────────────────────────────
-- 2D. Verificação final — deve retornar 0 para condominio-teste
SELECT 'demandas visíveis no sandbox' as check, COUNT(*) as deve_ser_zero
FROM demandas WHERE condo_id = 'condominio-teste' AND deletada_em IS NULL
UNION ALL
SELECT 'eventos portaria no sandbox',  COUNT(*)
FROM portaria_eventos WHERE condo_id = 'condominio-teste'
UNION ALL
SELECT 'manutencoes visíveis no sandbox', COUNT(*)
FROM manutencoes WHERE condo_id = 'condominio-teste' AND deletada_em IS NULL;

-- ════════════════════════════════════════════════════════════════════
-- FIM DO SCRIPT
-- Após rodar, acesse o portal do Síndico e confirme que
-- cada condomínio mostra apenas dados reais.
-- ════════════════════════════════════════════════════════════════════
