// BlokZip 휴대폰 앱 공용 사진 AI 중계 — 지금은 바이타블록(음식 사진·처방전)만
// 앱 안에 OpenRouter 키를 넣지 않기 위한 서버 함수. 키는 Supabase 비밀 값에만 있다
// (OPENROUTER_KEY_VITABLOK, 없으면 OPENROUTER_API_KEY)
//
// 보호 장치
// - x-blok-app 머리말이 등록된 앱 이름일 때만 받는다
// - 앱은 사진과 "무슨 일인지(task)"만 보낸다. 질문 글과 모델은 서버에 고정 — 아무 질문이나 대신 묻는 통로가 되지 않게
// - 사진 크기 제한, 같은 주소에서 10분에 20번까지
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-blok-app',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ALLOWED_APPS = new Set(['vitablok'])
const MODEL = 'google/gemini-3.5-flash-lite'
const MAX_IMAGE_CHARS = 12_000_000 // base64 기준 약 9MB
const ALLOWED_MEDIA = new Set(['image/jpeg', 'image/png', 'image/heic', 'image/webp'])
const WINDOW_MS = 10 * 60 * 1000
const WINDOW_LIMIT = 20
const hits = new Map<string, number[]>()

const PROMPTS: Record<string, string> = {
  food: `이 사진에 있는 음식을 분석해주세요.
반드시 아래 JSON 배열 형식으로만 답하세요. 마크다운이나 설명 없이 순수 JSON만:

[{"name":"음식 이름","calories":칼로리숫자,"carbs":탄수화물g숫자,"protein":단백질g숫자,"fat":지방g숫자}]

규칙:
- 사진에 보이는 음식을 한국식 이름으로 나열
- 칼로리는 사진 속 양 기준 추정 (kcal)
- 영양소는 그램(g) 단위 숫자만
- 음식이 없으면 빈 배열 [] 반환`,
  prescription: `이 처방전 이미지에서 약품 정보를 추출해주세요.
반드시 아래 JSON 배열 형식으로만 답하세요. 설명이나 다른 텍스트는 절대 포함하지 마세요.

[
  { "name": "약 이름", "dose": "용량 (예: 1정, 5mg 1정)", "time": "08:30" }
]

규칙:
- time 은 복용 시각을 24시간 "HH:MM" 형식으로만 적는다
- 아침 식후 = 08:30, 점심 식후 = 12:30, 저녁 식후 = 18:30, 취침 전 = 22:00 (식전이면 30분 앞당긴다)
- 하루 여러 번 먹는 약은 복용 시각마다 항목을 따로 나눈다 (예: 1일 3회 → 08:30, 12:30, 18:30 세 항목)
- 시각을 알 수 없으면 time 은 빈 문자열 ""

처방전에서 약품을 찾을 수 없으면 빈 배열 []을 반환하세요.`,
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function tooMany(key: string) {
  const now = Date.now()
  const list = (hits.get(key) ?? []).filter((t) => now - t < WINDOW_MS)
  list.push(now)
  hits.set(key, list)
  return list.length > WINDOW_LIMIT
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: { message: 'Method not allowed' } }, 405)

  const app = req.headers.get('x-blok-app') ?? ''
  if (!ALLOWED_APPS.has(app)) return json({ error: { message: 'Unknown app' } }, 403)

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown'
  if (tooMany(`${app}:${ip}`)) return json({ error: { message: '잠시 후 다시 시도해 주세요.' } }, 429)

  const apiKey = Deno.env.get(`OPENROUTER_KEY_${app.toUpperCase()}`) || Deno.env.get('OPENROUTER_API_KEY') || ''
  if (!apiKey) return json({ error: { message: 'API key not configured on server' } }, 500)

  try {
    const body = await req.json()
    const prompt = PROMPTS[String(body?.task ?? '')]
    if (!prompt) return json({ error: { message: 'task 가 올바르지 않습니다.' } }, 400)
    const image = typeof body?.image === 'string' ? body.image : ''
    if (!image) return json({ error: { message: '사진이 없습니다.' } }, 400)
    if (image.length > MAX_IMAGE_CHARS) return json({ error: { message: '사진이 너무 큽니다.' } }, 413)
    const mediaType = ALLOWED_MEDIA.has(body?.mediaType) ? body.mediaType : 'image/jpeg'

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: [
            { type: 'image_url', image_url: { url: `data:${mediaType};base64,${image}` } },
            { type: 'text', text: prompt },
          ],
        }],
      }),
    })
    const text = await response.text()
    return new Response(text, { status: response.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err) {
    return json({ error: { message: (err as Error).message || 'Server error' } }, 500)
  }
})
