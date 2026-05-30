-- ═══════════════════════════════════════════════════════════════════════════
-- FIX ALTO #8 (Auditoria 360 — 29/05/2026)
-- Adiciona soft-delete em manutencoes (NBR 5674 § 5.3 — rastreabilidade).
--
-- Antes:
--   - DELETE físico via sb.from('manutencoes').delete().eq('id',id)
--   - UPDATE direto sem snapshot
--   → Síndica podia reescrever histórico antes da validação.
--
-- Depois:
--   - Excluir = UPDATE marcando deletada_em + deletada_por_nome + motivo
--   - Listagem filtra por deletada_em IS NULL
--   - Histórico mantém registro acessível para auditoria/perícia
--
-- Rode no editor SQL do Supabase (project diagnostika-pmp).
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Adiciona colunas de soft-delete (se ainda não existem)
ALTER TABLE manutencoes
  ADD COLUMN IF NOT EXISTS deletada_em        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deletada_por_nome  TEXT,
  ADD COLUMN IF NOT EXISTS deletada_motivo    TEXT,
  -- Validação pela equipe técnica (PMP — fix ALTO #11 auditoria)
  ADD COLUMN IF NOT EXISTS validada_em        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS validada_por       TEXT,
  -- Parecer técnico opcional emitido pela equipe Diagnóstika
  ADD COLUMN IF NOT EXISTS parecer_emitido_em TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS parecer_emitido_por TEXT;

-- 2. Índice parcial para acelerar consultas de listagem (ignora os excluídos)
CREATE INDEX IF NOT EXISTS idx_manutencoes_ativas
  ON manutencoes(condo_id, data_execucao DESC)
  WHERE deletada_em IS NULL;

-- 3. Index para auditoria (busca por excluídos)
CREATE INDEX IF NOT EXISTS idx_manutencoes_excluidas
  ON manutencoes(condo_id, deletada_em DESC)
  WHERE deletada_em IS NOT NULL;

-- 4. (OPCIONAL — Recomendado) Bloquear DELETE físico em manutencoes via policy.
--    Revogando a policy de delete, o frontend nunca consegue apagar fisicamente.
DROP POLICY IF EXISTS "manutencoes_delete_owner" ON manutencoes;
DROP POLICY IF EXISTS "manutencoes_delete_authenticated" ON manutencoes;
-- (não recriamos — DELETE fica negado por default com RLS ativo)

-- 5. (OPCIONAL — quando quiser ir além) Tabela de auditoria com snapshot
--    histórico de toda alteração. Descomente quando for implementar a aba
--    "Histórico de alterações" no Síndico.
--
-- CREATE TABLE IF NOT EXISTS manutencao_historico (
--   id              BIGSERIAL PRIMARY KEY,
--   manutencao_id   UUID NOT NULL REFERENCES manutencoes(id) ON DELETE CASCADE,
--   acao            TEXT NOT NULL CHECK (acao IN ('criada','editada','validada','excluida','revertida')),
--   snapshot_antes  JSONB,
--   snapshot_depois JSONB,
--   quem_user_id    UUID,
--   quem_nome       TEXT,
--   quando          TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- );
-- CREATE INDEX idx_mnt_hist ON manutencao_historico(manutencao_id, quando DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICAÇÃO
-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Conferir colunas:
--    \d manutencoes
--
-- 2. Verificar contagem de excluídos vs ativos:
--    SELECT
--      COUNT(*) FILTER (WHERE deletada_em IS NULL) AS ativas,
--      COUNT(*) FILTER (WHERE deletada_em IS NOT NULL) AS excluidas
--    FROM manutencoes;
-- ═══════════════════════════════════════════════════════════════════════════
