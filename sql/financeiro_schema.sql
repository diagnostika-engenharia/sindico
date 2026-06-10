-- ============================================================
-- SCHEMA — Sistema Financeiro Diagnóstika (Supabase/PostgreSQL)
-- Migrado de MySQL/TiDB para o projeto Supabase existente
-- Todas as tabelas com prefixo fin_ para evitar conflitos
-- ============================================================

-- Habilitar UUID (já deve estar ativo no Supabase)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─── fin_contas_bancarias ────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_contas_bancarias (
  id          SERIAL PRIMARY KEY,
  nome        VARCHAR(255) NOT NULL,
  banco       VARCHAR(255) NOT NULL,
  agencia     VARCHAR(20),
  conta       VARCHAR(50),
  saldo       INTEGER NOT NULL DEFAULT 0,  -- em centavos
  ativa       BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_contas_receber ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_contas_receber (
  id                   SERIAL PRIMARY KEY,
  cliente              VARCHAR(255) NOT NULL,
  categoria            VARCHAR(50) NOT NULL DEFAULT 'Outros',
  descricao            TEXT,
  valor                INTEGER NOT NULL,  -- em centavos
  dia_vencimento       INTEGER NOT NULL,
  data_vencimento      VARCHAR(10) NOT NULL,  -- DD/MM/YYYY
  data_recebimento     VARCHAR(10),
  forma_pagamento      VARCHAR(50),
  status               VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  recorrente           BOOLEAN NOT NULL DEFAULT false,
  data_fim_recorrencia VARCHAR(7),  -- "dez/26"
  lembrete_nota_fiscal BOOLEAN NOT NULL DEFAULT false,
  nota_fiscal_emitida  BOOLEAN NOT NULL DEFAULT false,
  estornado            BOOLEAN NOT NULL DEFAULT false,
  data_estorno         VARCHAR(10),
  motivo_estorno       TEXT,
  comprovante          TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_contas_pagar ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_contas_pagar (
  id                   SERIAL PRIMARY KEY,
  categoria            VARCHAR(50) NOT NULL,
  fornecedor           VARCHAR(255) NOT NULL,
  descricao            TEXT,
  valor                INTEGER NOT NULL,  -- em centavos
  dia_vencimento       INTEGER NOT NULL,
  data_vencimento      VARCHAR(10) NOT NULL,  -- DD/MM/YYYY
  data_pagamento       VARCHAR(10),
  conta_bancaria_id    INTEGER REFERENCES fin_contas_bancarias(id),
  status               VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  recorrente           BOOLEAN NOT NULL DEFAULT false,
  data_fim_recorrencia VARCHAR(7),
  estornado            BOOLEAN NOT NULL DEFAULT false,
  data_estorno         VARCHAR(10),
  motivo_estorno       TEXT,
  comprovante          TEXT,
  -- Integração Reembolsos↔Contas a Pagar (ver sql/reembolsos_integracao_pagar.sql)
  competencia          VARCHAR(7),   -- "abr/26" (mesma chave de fin_reembolsos.mes); NULL = conta comum
  tipo_reembolso       VARCHAR(10),  -- 'visita' (Claudemir) | 'digital' (Rogério) | NULL
  responsavel_user_id  UUID,         -- dono do reembolso
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Idempotência: no máximo 1 conta por (competência, tipo de reembolso)
CREATE UNIQUE INDEX IF NOT EXISTS uq_cp_reembolso ON fin_contas_pagar (competencia, tipo_reembolso);

-- ─── fin_reembolsos ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_reembolsos (
  id                       SERIAL PRIMARY KEY,
  user_id                  UUID NOT NULL REFERENCES auth.users(id),
  data                     VARCHAR(10) NOT NULL,
  descricao                TEXT NOT NULL,
  cidade                   VARCHAR(100),
  valor                    INTEGER NOT NULL,  -- em centavos
  status                   VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  mes                      VARCHAR(7) NOT NULL,  -- "nov/25"
  google_event_id          VARCHAR(255),
  google_event_instance_id VARCHAR(512),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, google_event_instance_id)
);

-- ─── fin_reembolsos_digitais ─────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_reembolsos_digitais (
  id              SERIAL PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  data            VARCHAR(10) NOT NULL,
  servico         VARCHAR(100) NOT NULL,
  descricao       TEXT,
  valor           INTEGER NOT NULL,  -- em centavos (sem IOF)
  iof             INTEGER NOT NULL DEFAULT 0,
  valor_total     INTEGER NOT NULL,  -- valor + IOF
  mes_referencia  VARCHAR(7) NOT NULL,
  status          VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  data_reembolso  VARCHAR(10),
  comprovante     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_salarios ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_salarios (
  id              SERIAL PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  mes             VARCHAR(7) NOT NULL,
  valor           INTEGER NOT NULL,  -- em centavos
  data_pagamento  VARCHAR(10),
  status          VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  comprovante     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_transacoes_bancarias ────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_transacoes_bancarias (
  id                 SERIAL PRIMARY KEY,
  conta_bancaria_id  INTEGER NOT NULL REFERENCES fin_contas_bancarias(id),
  data               VARCHAR(10) NOT NULL,
  descricao          TEXT NOT NULL,
  valor              INTEGER NOT NULL,  -- centavos (+ crédito, - débito)
  tipo               VARCHAR(10) NOT NULL,  -- 'Crédito' | 'Débito'
  categoria          VARCHAR(100),
  tipo_categoria     VARCHAR(10),  -- 'Receita' | 'Despesa'
  conta_receber_ref  INTEGER REFERENCES fin_contas_receber(id),
  conta_pagar_ref    INTEGER REFERENCES fin_contas_pagar(id),
  status             VARCHAR(20) NOT NULL DEFAULT 'Pendente',
  observacao         TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_livro_caixa_cofre ───────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_livro_caixa_cofre (
  id                SERIAL PRIMARY KEY,
  user_id           UUID NOT NULL REFERENCES auth.users(id),
  data              VARCHAR(10) NOT NULL,
  tipo              VARCHAR(10) NOT NULL,  -- 'Entrada' | 'Saída'
  descricao         TEXT NOT NULL,
  valor             INTEGER NOT NULL,
  saldo_anterior    INTEGER NOT NULL,
  saldo_atual       INTEGER NOT NULL,
  conta_receber_ref INTEGER REFERENCES fin_contas_receber(id),
  origem            VARCHAR(50),
  observacao        TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── fin_relatorios ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_relatorios (
  id                      SERIAL PRIMARY KEY,
  numero_controle         VARCHAR(20) NOT NULL UNIQUE,
  tipo                    VARCHAR(50) NOT NULL,
  user_id                 UUID NOT NULL REFERENCES auth.users(id),
  mes_referencia          VARCHAR(7) NOT NULL,
  valor_total             INTEGER NOT NULL,
  quantidade_lancamentos  INTEGER NOT NULL,
  pdf_base64              TEXT,
  status                  VARCHAR(20) NOT NULL DEFAULT 'Gerado',
  conta_pagar_id          INTEGER REFERENCES fin_contas_pagar(id),
  data_geracao            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Triggers updated_at ─────────────────────────────────────
CREATE OR REPLACE FUNCTION fin_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DO $$ DECLARE t TEXT;
BEGIN
  FOR t IN SELECT unnest(ARRAY[
    'fin_contas_bancarias','fin_contas_receber','fin_contas_pagar',
    'fin_reembolsos','fin_reembolsos_digitais','fin_salarios',
    'fin_transacoes_bancarias','fin_livro_caixa_cofre','fin_relatorios'
  ]) LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_%s_updated ON %s', t, t);
    EXECUTE format('CREATE TRIGGER trg_%s_updated BEFORE UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION fin_set_updated_at()', t, t);
  END LOOP;
END $$;

-- ─── RLS ─────────────────────────────────────────────────────
ALTER TABLE fin_contas_bancarias   ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_contas_receber     ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_contas_pagar       ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_reembolsos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_reembolsos_digitais ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_salarios           ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_transacoes_bancarias ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_livro_caixa_cofre  ENABLE ROW LEVEL SECURITY;
ALTER TABLE fin_relatorios         ENABLE ROW LEVEL SECURITY;

-- Tabelas globais (contas bancárias, receber, pagar) — todos autenticados leem/escrevem
CREATE POLICY "fin_auth_all" ON fin_contas_bancarias    FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_contas_receber      FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_contas_pagar        FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_transacoes_bancarias FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_livro_caixa_cofre   FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_relatorios          FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Reembolsos = visão consolidada da empresa (Visita=Claudemir, Digital=Rogério);
-- ambos os sócios precisam enxergar todo o histórico → fin_auth_all.
CREATE POLICY "fin_auth_all" ON fin_reembolsos          FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "fin_auth_all" ON fin_reembolsos_digitais FOR ALL TO authenticated USING (true) WITH CHECK (true);
-- Salários permanecem privados por usuário.
CREATE POLICY "fin_own"      ON fin_salarios            FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ─── fin_google_tokens ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_google_tokens (
  id              SERIAL PRIMARY KEY,
  user_id         UUID NOT NULL UNIQUE REFERENCES auth.users(id),
  access_token    TEXT NOT NULL,
  refresh_token   TEXT,
  expires_at      TIMESTAMPTZ,
  calendar_id     VARCHAR(255) DEFAULT 'primary',
  sync_enabled    BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE fin_google_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fin_own" ON fin_google_tokens FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ─── fin_cidade_aprendizado ──────────────────────────────────
CREATE TABLE IF NOT EXISTS fin_cidade_aprendizado (
  id              SERIAL PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  texto_original  TEXT NOT NULL,
  palavra_chave   VARCHAR(255) NOT NULL,
  cidade_correta  VARCHAR(100) NOT NULL,
  valor_reembolso INTEGER NOT NULL DEFAULT 0,
  confianca       INTEGER NOT NULL DEFAULT 100,
  vezes_usado     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE fin_cidade_aprendizado ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fin_own" ON fin_cidade_aprendizado FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- coluna cidade adicionada na fin_reembolsos
ALTER TABLE fin_reembolsos ADD COLUMN IF NOT EXISTS cidade VARCHAR(100);

-- ─── Dados iniciais — contas bancárias ───────────────────────
INSERT INTO fin_contas_bancarias (nome, banco, agencia, conta, saldo) VALUES
  ('Conta Principal', 'Bradesco', '', '', 0),
  ('Conta Poupança',  'Bradesco', '', '', 0)
ON CONFLICT DO NOTHING;
