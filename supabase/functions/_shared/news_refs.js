// 9단계(예화) 현대 언론 예화용 — 네이버 API HUB 뉴스 검색으로 실제 기사를 찾아 AI 에게 넘긴다
// 키: NAVER_HUB_CLIENT_ID / NAVER_HUB_CLIENT_SECRET (서버 비밀값)

const NEWS_URL = 'https://naverapihub.apigw.ntruss.com/search/v1/news'

// 주소 → 언론사 이름 (자주 나오는 곳만, 없으면 주소의 도메인을 그대로)
const PRESS = {
  // 더 자세한 주소를 먼저 (sports.chosun.com 은 조선일보가 아니라 스포츠조선)
  'sports.chosun.com': '스포츠조선', 'biz.chosun.com': '조선비즈', 'sports.donga.com': '스포츠동아', 'isplus.com': '일간스포츠',
  'tf.co.kr': '더팩트', 'tvreport.co.kr': 'TV리포트', 'seoulfn.com': '서울파이낸스', 'taxwatch.co.kr': '택스워치',
  'bizwatch.co.kr': '비즈니스워치', 'zdnet.co.kr': '지디넷코리아', 'etnews.com': '전자신문', 'dt.co.kr': '디지털타임스',
  'chosun.com': '조선일보', 'joongang.co.kr': '중앙일보', 'donga.com': '동아일보', 'hani.co.kr': '한겨레',
  'khan.co.kr': '경향신문', 'hankookilbo.com': '한국일보', 'kmib.co.kr': '국민일보', 'seoul.co.kr': '서울신문',
  'segye.com': '세계일보', 'munhwa.com': '문화일보', 'mk.co.kr': '매일경제', 'hankyung.com': '한국경제',
  'sedaily.com': '서울경제', 'mt.co.kr': '머니투데이', 'edaily.co.kr': '이데일리', 'asiae.co.kr': '아시아경제',
  'yna.co.kr': '연합뉴스', 'yonhapnewstv.co.kr': '연합뉴스TV', 'newsis.com': '뉴시스', 'news1.kr': '뉴스1',
  'kbs.co.kr': 'KBS', 'imbc.com': 'MBC', 'sbs.co.kr': 'SBS', 'jtbc.co.kr': 'JTBC', 'ytn.co.kr': 'YTN',
  'mbn.co.kr': 'MBN', 'ichannela.com': '채널A', 'tvchosun.com': 'TV조선', 'ohmynews.com': '오마이뉴스',
  'nocutnews.co.kr': '노컷뉴스', 'pressian.com': '프레시안', 'heraldcorp.com': '헤럴드경제', 'fnnews.com': '파이낸셜뉴스',
  'christiantoday.co.kr': '크리스천투데이', 'kidok.com': '기독신문', 'newsnjoy.or.kr': '뉴스앤조이',
}

function pressOf(url) {
  try {
    const host = new URL(url).hostname.replace(/^www\./, '')
    for (const [d, name] of Object.entries(PRESS)) if (host === d || host.endsWith('.' + d)) return name
    return host
  } catch { return '' }
}

const clean = s => String(s || '').replace(/<[^>]+>/g, '')
  .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').trim()

// "Sat, 07 Nov 2026 19:31:29 +0900" → "2026-11-07" (한국 시간)
function ymd(pubDate) {
  const t = Date.parse(pubDate || '')
  if (isNaN(t)) return ''
  return new Date(t + 9 * 3600 * 1000).toISOString().slice(0, 10)
}

async function searchNews(query, id, secret) {
  const url = `${NEWS_URL}?query=${encodeURIComponent(query)}&display=5&sort=sim`
  const r = await fetch(url, { headers: { 'X-NCP-APIGW-API-KEY-ID': id, 'X-NCP-APIGW-API-KEY': secret } })
  if (!r.ok) return []
  const j = await r.json()
  return Array.isArray(j?.items) ? j.items : []
}

/// 본문(과 강조 주제)에 맞는 실제 기사 목록 글 — 검색어는 AI 가 짧게 만든다. 실패하면 ''
export async function newsRefsFor({ passage, emphasis, deepseekKey }) {
  const id = Deno.env.get('NAVER_HUB_CLIENT_ID') ?? '', secret = Deno.env.get('NAVER_HUB_CLIENT_SECRET') ?? ''
  if (!id || !secret || !passage) return ''
  // 1) 검색어 3개
  let keywords = []
  try {
    const r = await fetch('https://api.deepseek.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${deepseekKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'deepseek-flash', thinking: { type: 'disabled' }, stream: false, max_tokens: 60,
        messages: [{ role: 'user', content: `성경 본문 "${passage}"${emphasis ? `(설교자가 강조할 주제: ${emphasis})` : ''}의 핵심 주제와 맞닿은 오늘날 한국 사회의 사건·현상을 뉴스에서 찾기 위한 짧은 검색어 3개를 만들어 주세요. 교회·종교 기사가 아니라 일상과 사회의 사건이 나오도록 하세요. 검색어만 쉼표로 구분해 쓰세요.` }],
      }),
    })
    const j = await r.json()
    keywords = String(j?.choices?.[0]?.message?.content || '').split(/[,，\n]/).map(s => s.replace(/["'`]/g, '').trim()).filter(Boolean).slice(0, 3)
  } catch { /* 검색어를 못 만들면 아래에서 끝 */ }
  if (!keywords.length) return ''
  // 2) 검색어마다 기사 5개 → 겹치는 기사 빼고 최대 12개
  const seen = new Set(), items = []
  for (const list of await Promise.all(keywords.map(k => searchNews(k, id, secret).catch(() => [])))) {
    for (const it of list) {
      const url = it.originallink || it.link
      if (!url || seen.has(url)) continue
      seen.add(url)
      items.push({ title: clean(it.title), press: pressOf(url), date: ymd(it.pubDate), url, summary: clean(it.description).slice(0, 160) })
      if (items.length >= 12) break
    }
  }
  if (!items.length) return ''
  return items.map((it, i) => `${i + 1}. 제목: ${it.title} | 언론사: ${it.press} | 보도일: ${it.date} | 주소: ${it.url}\n   요약: ${it.summary}`).join('\n')
}
