-- ════════════════════════════════════════════════════════════════
-- Reembolsos: visão consolidada da empresa
-- Visita  = trabalho de campo do Claudemir
-- Digital = trabalho remoto do Rogério
-- Objetivo: o painel Financeiro (Rogério) enxergar TODO o histórico
--           de reembolsos de visita, incluindo mar/26 e abr/26.
--
-- Rodar em: Supabase Dashboard → SQL Editor → New query → Run
-- Projeto: fimmjgdwhifsrrbreche
-- ════════════════════════════════════════════════════════════════

-- 1) Troca o RLS de "cada um vê só o seu" (fin_own) por visão de empresa
--    (fin_auth_all), igual já é feito nas outras tabelas financeiras.
DROP POLICY IF EXISTS "fin_own" ON fin_reembolsos;
DROP POLICY IF EXISTS "fin_own" ON fin_reembolsos_digitais;

CREATE POLICY "fin_auth_all" ON fin_reembolsos
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "fin_auth_all" ON fin_reembolsos_digitais
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- 2) Conferência: quantos reembolsos de visita existem por mês (todos os usuários)
SELECT mes, count(*) AS qtd, sum(valor)/100.0 AS total_reais
FROM fin_reembolsos
GROUP BY mes
ORDER BY min(data);
-- Esperado após migração completa: nov/25, dez/25, jan/26, fev/26, mar/26, abr/26
