// 바이블블록 AI 중계 — 로그인한 사용자만 DeepSeek 을 부를 수 있다 (웹 api/generate.ts 의 잠금 있는 버전)
// - Supabase 로그인 토큰을 확인하고, 없으면 401
// - 모델·최대 길이는 서버에서 고정해 다른 용도로 쓰이지 않게 한다
// - 브라우저(플러터 웹)에서도 읽을 수 있도록 모든 응답에 CORS 허가를 붙인다
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_API_KEY') ?? ''
const MAX_TOKENS = 8000

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: { message: 'Method not allowed' } }, 405)

  // 로그인 확인 (익명 키만으로는 통과하지 못한다)
  const supabase = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  })
  const { data: { user } } = await supabase.auth.getUser()
  // 익명 로그인(anonymous) 계정은 받지 않는다 — 누구나 만들 수 있어 잠금이 무의미해진다
  if (!user || user.is_anonymous) return json({ error: { message: '로그인이 필요합니다.' } }, 401)
  if (!DEEPSEEK_API_KEY) return json({ error: { message: 'API key not configured on server' } }, 500)

  try {
    const body = await req.json()
    const messages = Array.isArray(body?.messages) ? body.messages : null
    if (!messages) return json({ error: { message: 'messages 가 없습니다.' } }, 400)
    const stream = body?.stream !== false
    const maxTokens = Math.min(Number(body?.max_tokens) || MAX_TOKENS, MAX_TOKENS)

    const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${DEEPSEEK_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'deepseek-chat', messages, stream, max_tokens: maxTokens }),
    })

    if (!response.ok) {
      const text = await response.text()
      let error
      try { error = JSON.parse(text) } catch { error = { error: { message: text || `HTTP ${response.status}` } } }
      return json(error, response.status)
    }

    return new Response(response.body, {
      headers: {
        ...corsHeaders,
        'Content-Type': stream ? 'text/event-stream' : 'application/json',
        'Cache-Control': 'no-cache',
      },
    })
  } catch (err) {
    return json({ error: { message: (err as Error).message || 'Server error' } }, 500)
  }
})
