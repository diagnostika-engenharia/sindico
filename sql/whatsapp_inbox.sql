-- ════════════════════════════════════════════════════════════════════
-- TABELA: whatsapp_inbox
-- Armazena documentos recebidos pelo WhatsApp/MegaZap aguardando
-- revisão e aprovação pelo engenheiro Diagnóstika.
-- Rode no SQL Editor do Supabase antes de ativar o webhook.
-- ════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS whatsapp_inbox (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Dados do remetente (quem enviou no WhatsApp)
  telefone         TEXT NOT NULL,
  nome_contato     TEXT,
  condo_id         TEXT,  -- associado manualmente ou por match de telefone

  -- Documento recebido
  doc_url          TEXT,  -- URL do arquivo no Supabase Storage
  doc_tipo         TEXT,  -- 'pdf' | 'imagem' | 'texto'
  doc_nome         TEXT,

  -- Dados extraídos pela IA
  ia_status        TEXT DEFAULT 'pendente', -- 'pendente' | 'processando' | 'ok' | 'erro'
  ia_modelo        TEXT,
  ia_raw           JSONB, -- resposta completa da IA

  -- Campos extraídos (preenchidos pela IA, revisados pelo engenheiro)
  solicitante_nome TEXT,
  solicitante_apto TEXT,
  solicitante_bloco TEXT,

  tipo_obra        TEXT,  -- 'simples' | 'complexa' | 'ampliacao'
  escopo_obra      TEXT,  -- descrição livre
  materiais        TEXT,
  prazo_inicio     DATE,
  prazo_fim        DATE,

  rt_nome          TEXT,  -- Responsável Técnico
  rt_crea_cau      TEXT,
  rt_art_numero    TEXT,
  tem_art          BOOLEAN,
  tem_memorial     BOOLEAN,

  conformidade_nbr TEXT,  -- 'conforme' | 'pendencias' | 'nao_conforme'
  pendencias       TEXT[], -- lista de pendências identificadas

  -- Fluxo de aprovação
  status           TEXT DEFAULT 'aguardando', -- 'aguardando' | 'em_analise' | 'aprovado' | 'reprovado' | 'pendente_docs'
  demanda_id       UUID REFERENCES demandas(id), -- quando convertido em demanda
  analisado_por    TEXT,
  analisado_em     TIMESTAMPTZ,
  parecer          TEXT,

  -- Metadados
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW(),
  source           TEXT DEFAULT 'whatsapp' -- 'whatsapp' | 'manual' | 'email'
);

-- Índices
CREATE INDEX IF NOT EXISTS idx_wai_status    ON whatsapp_inbox(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_wai_telefone  ON whatsapp_inbox(telefone);
CREATE INDEX IF NOT EXISTS idx_wai_condo     ON whatsapp_inbox(condo_id, status);

-- RLS
ALTER TABLE whatsapp_inbox ENABLE ROW LEVEL SECURITY;

-- Apenas authenticated pode ler/escrever (engenheiros Diagnóstika)
CREATE POLICY "wai_select_auth" ON whatsapp_inbox FOR SELECT TO authenticated USING (true);
CREATE POLICY "wai_insert_auth" ON whatsapp_inbox FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "wai_update_auth" ON whatsapp_inbox FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

-- Service role (Edge Function) pode INSERT e UPDATE
CREATE POLICY "wai_insert_service" ON whatsapp_inbox FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "wai_update_service" ON whatsapp_inbox FOR UPDATE TO service_role USING (true) WITH CHECK (true);

-- Bucket para documentos recebidos via WhatsApp
INSERT INTO storage.buckets (id, name, public)
VALUES ('whatsapp-docs', 'whatsapp-docs', false)
ON CONFLICT (id) DO NOTHING;

-- Policy de upload para service_role (Edge Function faz o upload)
CREATE POLICY "wai_docs_upload_service"
  ON storage.objects FOR INSERT TO service_role
  WITH CHECK (bucket_id = 'whatsapp-docs');

CREATE POLICY "wai_docs_read_auth"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'whatsapp-docs');
