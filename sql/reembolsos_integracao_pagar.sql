-- ════════════════════════════════════════════════════════════════
-- Integração Reembolsos ↔ Contas a Pagar (ciclo de vida + idempotência)
--
-- Fluxo: Gerar relatório → cria conta a pagar 'Aguardando aprovação'
--        → 1 clique "Aprovar e lançar" (status Pendente)
--        → Pagar → cascata: reembolsos do mês viram 'Pago'
--
-- Responsável por tipo: Visita = Claudemir, Digital = Rogério.
-- Idempotente: no máximo 1 conta por (competência, tipo de reembolso).
--
-- Rodar em: Supabase SQL Editor — Projeto fimmjgdwhifsrrbreche
-- ════════════════════════════════════════════════════════════════

ALTER TABLE fin_contas_pagar ADD COLUMN IF NOT EXISTS competencia          VARCHAR(7);   -- ex.: "abr/26" (mesma chave usada em fin_reembolsos.mes)
ALTER TABLE fin_contas_pagar ADD COLUMN IF NOT EXISTS tipo_reembolso       VARCHAR(10);  -- 'visita' | 'digital' | NULL (conta comum)
ALTER TABLE fin_contas_pagar ADD COLUMN IF NOT EXISTS responsavel_user_id  UUID;         -- dono do reembolso (Claudemir/Rogério)

-- Índice único NÃO-parcial: contas comuns (competencia/tipo NULL) coexistem
-- (NULL ≠ NULL no índice único), e cada (competência, tipo) de reembolso é único.
-- Não-parcial para que o UPSERT (ON CONFLICT) do PostgREST consiga inferir.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cp_reembolso
  ON fin_contas_pagar (competencia, tipo_reembolso);

-- Conferência
SELECT column_name, data_type FROM information_schema.columns
WHERE table_name='fin_contas_pagar' AND column_name IN ('competencia','tipo_reembolso','responsavel_user_id');
