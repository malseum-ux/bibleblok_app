// 예배인도 참고 자료 — 날짜를 교회력·달력 위치로 바꾸고, 같은 위치의 자료를 골라 AI 에게 줄 글로 만든다
// 자료는 서버 비공개 표 worship_refs 에 있다 (supabase/sql/003_worship_refs.sql). 자료 넣기: scripts/load_worship_refs.mjs

const DAY = 86400000

function utc(y, m, d) { return Date.UTC(y, m - 1, d) }

function easterOf(year) {
  const a = year % 19, b = Math.floor(year / 100), c = year % 100
  const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3)
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4
  const l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451)
  const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1
  return utc(year, month, day)
}

// 대림절 첫 주일 (성탄절 전 넷째 주일)
function adventOf(year) {
  const xmas = utc(year, 12, 25)
  const dow = new Date(xmas).getUTCDay()
  return xmas - (dow === 0 ? 28 : dow + 21) * DAY
}

/// 교회력 위치: advent-1~4, christmas, dec31, jan1, epiphany-N, lent-1~5, palm, holyweek, easter, easter-2~7, pentecost, pent-N
export function litKey(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number)
  const t = utc(y, m, d)
  if (m === 12 && d === 31) return 'dec31'
  if (m === 1 && d === 1) return 'jan1'
  const advent = adventOf(y)
  if (t >= advent && t < utc(y, 12, 25)) return `advent-${Math.floor((t - advent) / (7 * DAY)) + 1}`
  if ((m === 12 && d >= 25) || (m === 1 && d <= 5)) return 'christmas'
  const easter = easterOf(y)
  const ashWed = easter - 46 * DAY
  const palm = easter - 7 * DAY
  const pentecost = easter + 49 * DAY
  if (t < ashWed) {
    const jan6 = utc(y, 1, 6)
    return `epiphany-${Math.floor((t - jan6) / (7 * DAY)) + 1}`
  }
  if (t < palm) return `lent-${Math.min(5, Math.floor((t - ashWed - 4 * DAY) / (7 * DAY)) + 1)}`
  if (t === palm) return 'palm'
  if (t < easter) return 'holyweek'
  if (t === easter) return 'easter'
  if (t < pentecost) return `easter-${Math.floor((t - easter) / (7 * DAY)) + 1}`
  if (t === pentecost) return 'pentecost'
  return `pent-${Math.floor((t - pentecost) / (7 * DAY))}`
}

/// 달력 위치: 주일이면 "11-sun3"(11월 셋째 주일), 아니면 "12-25"
export function civilKey(dateStr) {
  const [y, m, d] = dateStr.split('-').map(Number)
  const dow = new Date(utc(y, m, d)).getUTCDay()
  return dow === 0 ? `${m}-sun${Math.floor((d - 1) / 7) + 1}` : `${m}-${d}`
}

// 달력으로 정해지는 특별 주일 — 이런 날은 교회력 위치보다 달력 위치가 우선
const SPECIAL = /추수|맥추|종교개혁|어린이|어버이|가정|스승|성서주일|광복|삼일|3[.·]?1절|6[.·]?25|한국전쟁|송구영신|신년|성탄|군선교|장애인|환경|교회창립|노동|민족|평화통일/

/// 그날에 맞는 자료 고르기 — 가장 잘 맞는 것부터 최대 limit 개
export function pickRefs(rows, dateStr, limit = 3) {
  const lk = litKey(dateStr), ck = civilKey(dateStr)
  const scored = rows.map(r => {
    let s = 0
    if (r.civil_key === ck && SPECIAL.test(r.occasion || '')) s += 5
    if (r.lit_key === lk) s += 3
    else if (r.civil_key === ck) s += 1
    return { r, s }
  }).filter(x => x.s > 0)
  scored.sort((a, b) => b.s - a.s || (a.r.date < b.r.date ? 1 : -1))
  return scored.slice(0, limit).map(x => x.r)
}

const v = x => (x && (x.ref || x.text)) ? `${x.ref || ''} ${x.text ? `"${x.text}"` : ''}`.trim() : ''
const hymns = list => (list || []).map(h => `${h.no}장 ${h.title || ''}`.trim()).join(', ')

/// AI 에게 줄 참고 자료 글
export function refsText(rows) {
  if (!rows?.length) return ''
  const parts = rows.map((r, i) => {
    const d = r.data || {}
    const lines = [`(${i + 1}) ${r.occasion || ''} · 본문 ${d.passage || ''}${d.color ? ` · 예전색 ${d.color}` : ''}`]
    const add = (label, val) => { if (val) lines.push(`- ${label}: ${val}`) }
    add('예배의 부름', v(d.callVerse))
    add('기원', d.invocation)
    add('참회에의 초대', d.confessionInvite)
    add('참회기도', d.confession)
    add('사함의 확인', v(d.pardon))
    add('목회기도', d.pastoralPrayer)
    add('헌금 성구', v(d.offeringVerse))
    add('봉헌기도', d.offeringPrayer)
    if (d.responsive?.no) add('성시교독', `${d.responsive.no}번 ${d.responsive.title || ''}`.trim())
    if (d.hymnal !== '통일찬송가') {
      add('설교 전 찬송', hymns(d.hymnsBefore))
      add('설교 후 찬송', hymns(d.hymnsAfter))
    }
    if (d.sermon?.theme || d.sermon?.title) add('설교 주제', [d.sermon.theme, d.sermon.title].filter(Boolean).join(' / '))
    return lines.join('\n')
  })
  return `[이 주일의 참고 자료 — 같은 교회력 주일에 실제 예배에서 쓰인 순서와 기도문]
아래 자료의 성구·교독문·찬송 선택과 기도문의 흐름·강조점·표현을 적극 참고하여 이번 예배인도를 작성하세요. 기도문은 자료를 바탕으로 이번 날짜와 성서정과에 맞게 새로 다듬어 쓰세요.

${parts.join('\n\n')}`
}
