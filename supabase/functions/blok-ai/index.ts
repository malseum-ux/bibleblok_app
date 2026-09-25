// BlokZip 휴대폰 앱 공용 AI 중계 — 아멘블록·이음·바이타블록·오토블록
// 앱 안에 DeepSeek 키를 넣지 않기 위한 서버 함수. 키는 Supabase 비밀 값에만 있다.
// 앱마다 키를 따로 쓴다 (DEEPSEEK_KEY_AMENBLOK 등) — 앱별 사용량을 딥식 화면에서 나눠 보기 위함
//
// 보호 장치 (로그인이 없는 앱도 있어 "로그인한 사람만" 받을 수는 없다)
// - x-blok-app 머리말이 등록된 앱 이름일 때만 받는다
// - 모델은 deepseek-flash, 생각 과정 끔 — 서버에서 고정
// - 최대 길이 4000 토큰, 보내는 글 60,000자까지
// - 같은 주소에서 10분에 60번까지 (서버 인스턴스마다 따로 센다 — 최소한의 과다 사용 방지)
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-blok-app',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ALLOWED_APPS = new Set(['amenblok', 'amiblok', 'vitablok', 'autoblok'])
const MAX_TOKENS = 4000
const MAX_INPUT_CHARS = 60000
const WINDOW_MS = 10 * 60 * 1000
const WINDOW_LIMIT = 60
const hits = new Map<string, number[]>()

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function tooMany(ip: string) {
  const now = Date.now()
  const list = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS)
  list.push(now)
  hits.set(ip, list)
  return list.length > WINDOW_LIMIT
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: { message: 'Method not allowed' } }, 405)

  const app = req.headers.get('x-blok-app') ?? ''
  if (!ALLOWED_APPS.has(app)) return json({ error: { message: 'Unknown app' } }, 403)

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown'
  if (tooMany(`${app}:${ip}`)) return json({ error: { message: '잠시 후 다시 시도해 주세요.' } }, 429)
  // 그 앱 전용 키 — 비어 있으면 예전 공용 키로 대신 작동
  const apiKey = Deno.env.get(`DEEPSEEK_KEY_${app.toUpperCase()}`) || Deno.env.get('DEEPSEEK_API_KEY') || ''
  if (!apiKey) return json({ error: { message: 'API key not configured on server' } }, 500)

  try {
    const body = await req.json()
    const messages = Array.isArray(body?.messages) ? body.messages : null
    if (!messages) return json({ error: { message: 'messages 가 없습니다.' } }, 400)
    const inputChars = messages.reduce((n: number, m: { content?: unknown }) => n + String(m?.content ?? '').length, 0)
    if (inputChars > MAX_INPUT_CHARS) return json({ error: { message: '요청이 너무 깁니다.' } }, 413)

    const payload: Record<string, unknown> = {
      model: 'deepseek-flash',
      thinking: { type: 'disabled' }, // 예전 deepseek-chat 과 같은 즉답 방식
      messages,
      max_tokens: Math.min(Number(body?.max_tokens) || 2000, MAX_TOKENS),
    }
    if (typeof body?.temperature === 'number') payload.temperature = body.temperature
    if (body?.response_format) payload.response_format = body.response_format

    const response = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    const text = await response.text()
    return new Response(text, { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err) {
    return json({ error: { message: (err as Error).message || 'Server error' } }, 500)
  }
})
