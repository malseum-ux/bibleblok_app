// 성경과설교 AI 중계 — 웹·플러터 두 앱이 함께 쓴다. 로그인한 사용자만 DeepSeek 을 부를 수 있다
// - 앱은 { kind, params } 만 보내고, 지시문은 여기서 조립한다 (../_shared/bibleblok_prompts.js)
//   → 지시문을 고치면 이 함수만 다시 올리면 모든 앱에 즉시 반영된다
// - Supabase 로그인 토큰을 확인하고, 없으면 401
// - 모델·최대 길이는 서버에서 고정해 다른 용도로 쓰이지 않게 한다
// - 브라우저(웹)에서도 읽을 수 있도록 모든 응답에 CORS 허가를 붙인다
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildRequest } from '../_shared/bibleblok_prompts.js'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// 성경과설교 전용 키 — 비어 있으면 예전 공용 키로 대신 작동
const DEEPSEEK_API_KEY = Deno.env.get('DEEPSEEK_KEY_BIBLEBLOK') || Deno.env.get('DEEPSEEK_API_KEY') || ''
const MAX_INPUT_CHARS = 300000 // 재료(연구 내용·초안 등) 전체 글자 수 상한

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

  // 구독 확인 — REQUIRE_SUBSCRIPTION=true 일 때만 (결제를 붙이기 전까지는 꺼 둔다)
  if (Deno.env.get('REQUIRE_SUBSCRIPTION') === 'true') {
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
    const { data: sub } = await admin.from('subscriptions')
      .select('status, expires_at').eq('user_id', user.id).eq('app', 'bibleblok').maybeSingle()
    const active = sub?.status === 'active' && (!sub.expires_at || new Date(sub.expires_at) > new Date())
    if (!active) return json({ error: { message: '구독이 필요합니다.', code: 'subscription_required' } }, 402)
  }

  try {
    const raw = await req.text()
    if (raw.length > MAX_INPUT_CHARS) return json({ error: { message: '요청이 너무 깁니다.' } }, 413)
    const body = JSON.parse(raw)
    const built = typeof body?.kind === 'string' ? buildRequest(body.kind, body.params) : null
    if (!built) return json({ error: { message: '알 수 없는 요청입니다.' } }, 400)
    const { messages, stream, maxTokens } = built

    const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${DEEPSEEK_API_KEY}`, 'Content-Type': 'application/json' },
      // thinking disabled — 생각 과정 끄기 (예전 deepseek-chat 과 같은 즉답 방식, flash 는 기본이 생각 모드)
      body: JSON.stringify({ model: 'deepseek-flash', thinking: { type: 'disabled' }, messages, stream, max_tokens: maxTokens }),
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
