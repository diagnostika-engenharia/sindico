/**
 * Edge Function: processar-whatsapp
 * Diagnóstika Engenharia — Webhook receptor do MegaZap/WhatsApp
 *
 * Fluxo:
 * 1. Recebe webhook do MegaZap quando cliente envia documento
 * 2. Baixa o documento (PDF/imagem) e salva no Storage
 * 3. Envia para OpenAI GPT-4o para extração completa de dados
 * 4. Salva resultado em whatsapp_inbox para revisão do engenheiro
 *
 * URL do webhook a configurar no MegaZap:
 *   https://fimmjgdwhifsrrbreche.supabase.co/functions/v1/processar-whatsapp
 *
 * Header de autenticação:
 *   Authorization: Bearer <MEGAZAP_WEBHOOK_SECRET>  (configurar no MegaZap)
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL      = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const OPENAI_KEY        = Deno.env.get("OPENAI_API_KEY")!;
const WEBHOOK_SECRET    = Deno.env.get("MEGAZAP_WEBHOOK_SECRET") || "";

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE);

// ─── Prompt de extração ──────────────────────────────────────────
const PROMPT_EXTRACAO = `
Você é um assistente especializado em análise de documentos de reforma condominial conforme a NBR 16.280:2020.

Analise o documento enviado e extraia TODAS as informações abaixo em JSON.
Se alguma informação não estiver presente, coloque null.
Seja preciso — esses dados serão usados para aprovação técnica formal.

Retorne APENAS o JSON, sem explicações:

{
  "solicitante_nome": "Nome completo do solicitante/morador",
  "solicitante_apto": "Número do apartamento",
  "solicitante_bloco": "Bloco ou torre",
  "condominio_nome": "Nome do condomínio se mencionado",

  "tipo_obra": "simples | complexa | ampliacao",
  "escopo_obra": "Descrição detalhada do que será feito",
  "materiais": "Principais materiais e acabamentos",
  "prazo_inicio": "DD/MM/AAAA ou null",
  "prazo_fim": "DD/MM/AAAA ou null",
  "area_afetada": "m² aproximados ou descrição da área",

  "rt_nome": "Nome do Responsável Técnico",
  "rt_crea_cau": "Número CREA ou CAU",
  "rt_art_numero": "Número da ART ou RRT",
  "tem_art": true | false,
  "tem_memorial": true | false,
  "tem_projeto": true | false,

  "pendencias": [
    "Lista de documentos ou informações faltando",
    "segundo item se houver"
  ],

  "conformidade_nbr": "conforme | pendencias | nao_conforme",
  "motivo_conformidade": "Justificativa da classificação",

  "resumo_ia": "Resumo em 2 linhas para o engenheiro",
  "alerta": "Algum ponto crítico de atenção ou null"
}

Critérios NBR 16.280:
- Reforma SIMPLES: sem interferência estrutural, sem remoção de paredes, sem alteração de instalações hidro/elétrica
- Reforma COMPLEXA: com interferência estrutural OU alteração de instalações
- AMPLIAÇÃO: aumento de área construída
- RT obrigatório para obras complexas e ampliações
- ART/RRT obrigatória quando há RT envolvido
`;

// ─── Extrai dados via OpenAI ─────────────────────────────────────
async function extrairDadosComIA(
  docUrl: string,
  docTipo: string,
  docNome: string
): Promise<Record<string, unknown>> {
  let mensagens: unknown[];

  if (docTipo === "imagem") {
    // Envia imagem diretamente para GPT-4o vision
    mensagens = [
      {
        role: "user",
        content: [
          { type: "text", text: PROMPT_EXTRACAO },
          { type: "image_url", image_url: { url: docUrl, detail: "high" } },
        ],
      },
    ];
  } else {
    // Para PDF: instrui a IA a interpretar com base no contexto
    // (em produção, use a Files API da OpenAI para PDFs maiores)
    mensagens = [
      {
        role: "user",
        content: `${PROMPT_EXTRACAO}\n\nDocumento: ${docNome}\nURL: ${docUrl}\n\nComo não consigo ler o PDF diretamente, analise com base no nome do arquivo e retorne o JSON com campos null onde não é possível determinar, adicionando em "pendencias" a necessidade de revisão manual.`,
      },
    ];
  }

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o",
      messages: mensagens,
      max_tokens: 1500,
      temperature: 0.1,
      response_format: { type: "json_object" },
    }),
  });

  if (!res.ok) throw new Error(`OpenAI error: ${res.status}`);
  const data = await res.json();
  const texto = data.choices?.[0]?.message?.content || "{}";
  return JSON.parse(texto);
}

// ─── Detecta tipo de documento ───────────────────────────────────
function detectarTipo(mimetype: string, nome: string): "pdf" | "imagem" | "texto" {
  if (mimetype?.includes("pdf") || nome?.endsWith(".pdf")) return "pdf";
  if (mimetype?.startsWith("image/")) return "imagem";
  return "texto";
}

// ─── Parser do webhook MegaZap ───────────────────────────────────
function parseMegaZap(body: Record<string, unknown>) {
  // MegaZap pode enviar em formatos ligeiramente diferentes dependendo da versão
  // Suportamos os dois formatos mais comuns
  const msg = (body.message || body.data || body) as Record<string, unknown>;

  const telefone = (
    msg.phone || msg.from || msg.sender ||
    (msg.contact as Record<string,unknown>)?.phone || ""
  ) as string;

  const nomeContato = (
    msg.contact_name || msg.name || msg.pushname ||
    (msg.contact as Record<string,unknown>)?.name || ""
  ) as string;

  const mediaUrl = (
    msg.media_url || msg.url || msg.file_url ||
    (msg.media as Record<string,unknown>)?.url || null
  ) as string | null;

  const mimetype = (
    msg.mimetype || msg.media_type ||
    (msg.media as Record<string,unknown>)?.mimetype || ""
  ) as string;

  const nomeArquivo = (
    msg.file_name || msg.filename ||
    (msg.media as Record<string,unknown>)?.filename || "documento"
  ) as string;

  const textoMensagem = (
    msg.text || msg.body || msg.message_text || ""
  ) as string;

  return { telefone, nomeContato, mediaUrl, mimetype, nomeArquivo, textoMensagem };
}

// ─── Tenta associar telefone a condomínio ────────────────────────
async function resolverCondo(telefone: string): Promise<string | null> {
  // Verifica se o telefone está cadastrado em algum morador/síndico
  const { data } = await sb
    .from("demandas")
    .select("condo_id, morador_telefone")
    .eq("morador_telefone", telefone)
    .limit(1)
    .maybeSingle();
  return data?.condo_id || null;
}

// ─── Salva documento no Storage ──────────────────────────────────
async function salvarDocumento(
  mediaUrl: string,
  nomeArquivo: string,
  telefone: string
): Promise<string> {
  const resp = await fetch(mediaUrl);
  const blob = await resp.blob();
  const buffer = await blob.arrayBuffer();

  const path = `${telefone}/${Date.now()}_${nomeArquivo}`;
  const { error } = await sb.storage
    .from("whatsapp-docs")
    .upload(path, buffer, { contentType: blob.type, upsert: false });

  if (error) throw new Error(`Storage upload: ${error.message}`);

  const { data: urlData } = sb.storage
    .from("whatsapp-docs")
    .getPublicUrl(path);

  return urlData.publicUrl;
}

// ─── Handler principal ───────────────────────────────────────────
serve(async (req) => {
  const headers = { "Content-Type": "application/json" };

  // Verifica secret do webhook
  if (WEBHOOK_SECRET) {
    const auth = req.headers.get("Authorization") || req.headers.get("X-Webhook-Secret") || "";
    if (!auth.includes(WEBHOOK_SECRET)) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers });
    }
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ ok: true, msg: "webhook ativo" }), { headers });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "JSON inválido" }), { status: 400, headers });
  }

  const { telefone, nomeContato, mediaUrl, mimetype, nomeArquivo, textoMensagem } = parseMegaZap(body);

  // Ignora mensagens sem documento
  if (!mediaUrl) {
    return new Response(JSON.stringify({ ok: true, msg: "mensagem sem documento — ignorada" }), { headers });
  }

  // Ignora mensagens de grupos (telefone com @g.us)
  if (telefone.includes("@g.us")) {
    return new Response(JSON.stringify({ ok: true, msg: "mensagem de grupo — ignorada" }), { headers });
  }

  // Cria registro inicial no inbox
  const { data: inbox, error: insErr } = await sb
    .from("whatsapp_inbox")
    .insert({
      telefone,
      nome_contato: nomeContato,
      doc_nome: nomeArquivo,
      doc_tipo: detectarTipo(mimetype, nomeArquivo),
      ia_status: "processando",
      source: "whatsapp",
    })
    .select()
    .single();

  if (insErr) {
    console.error("Insert inbox:", insErr);
    return new Response(JSON.stringify({ error: insErr.message }), { status: 500, headers });
  }

  // Processamento assíncrono (não bloqueia resposta ao MegaZap)
  EdgeRuntime.waitUntil((async () => {
    try {
      // 1. Salva documento no Storage
      const docUrl = await salvarDocumento(mediaUrl, nomeArquivo, telefone);
      const docTipo = detectarTipo(mimetype, nomeArquivo);

      // 2. Tenta associar ao condomínio
      const condoId = await resolverCondo(telefone);

      // 3. Extrai dados com IA
      const dadosIA = await extrairDadosComIA(docUrl, docTipo, nomeArquivo);

      // 4. Atualiza registro no inbox
      await sb.from("whatsapp_inbox").update({
        doc_url:          docUrl,
        doc_tipo:         docTipo,
        condo_id:         condoId || (dadosIA.condominio_nome ? null : null),
        ia_status:        "ok",
        ia_modelo:        "gpt-4o",
        ia_raw:           dadosIA,
        solicitante_nome: dadosIA.solicitante_nome,
        solicitante_apto: dadosIA.solicitante_apto,
        solicitante_bloco:dadosIA.solicitante_bloco,
        tipo_obra:        dadosIA.tipo_obra,
        escopo_obra:      dadosIA.escopo_obra,
        materiais:        dadosIA.materiais,
        prazo_inicio:     dadosIA.prazo_inicio,
        prazo_fim:        dadosIA.prazo_fim,
        rt_nome:          dadosIA.rt_nome,
        rt_crea_cau:      dadosIA.rt_crea_cau,
        rt_art_numero:    dadosIA.rt_art_numero,
        tem_art:          dadosIA.tem_art,
        tem_memorial:     dadosIA.tem_memorial,
        pendencias:       dadosIA.pendencias,
        conformidade_nbr: dadosIA.conformidade_nbr,
        status:           "aguardando",
        updated_at:       new Date().toISOString(),
      }).eq("id", inbox.id);

      console.log(`✅ Inbox ${inbox.id} processado — ${dadosIA.conformidade_nbr}`);
    } catch (err) {
      console.error("Erro processamento:", err);
      await sb.from("whatsapp_inbox").update({
        ia_status: "erro",
        ia_raw: { erro: String(err) },
        updated_at: new Date().toISOString(),
      }).eq("id", inbox.id);
    }
  })());

  // Responde imediatamente ao MegaZap (webhook precisa de 200 rápido)
  return new Response(
    JSON.stringify({ ok: true, inbox_id: inbox.id, msg: "documento recebido e em processamento" }),
    { headers }
  );
});
