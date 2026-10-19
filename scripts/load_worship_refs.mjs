// 예배인도 참고 자료 넣기 — 뽑아 둔 worship_YYYY.json 들을 서버 비공개 표 worship_refs 에 넣는다
// 자료 파일은 저장소에 넣지 않는다 (저장소는 공개). 선생님 맥의 자료 폴더에서 읽는다
// 사용: node scripts/load_worship_refs.mjs <자료 폴더> "<자료 이름>"
//   → 같은 자료 이름의 예전 행을 지우고 새로 넣는다 (해마다 SQL 파일 하나씩 만들어 supabase db query 로 실행)
import { readFileSync, readdirSync, writeFileSync, mkdtempSync } from 'node:fs'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { execFileSync } from 'node:child_process'
import { litKey, civilKey } from '../supabase/functions/_shared/worship_refs.js'

const [dir, name] = process.argv.slice(2)
if (!dir || !name) { console.error('사용: node scripts/load_worship_refs.mjs <자료 폴더> "<자료 이름>"'); process.exit(1) }

const PROJECT = 'pdrxuxrlwreqgiptzily'
const q = s => `'${String(s).replace(/'/g, "''")}'`
const tmp = mkdtempSync(join(tmpdir(), 'wrefs-'))
const run = file => execFileSync('supabase', ['db', 'query', '--linked', '--project-ref', PROJECT, '-f', file], { stdio: ['ignore', 'pipe', 'inherit'] })

const files = readdirSync(dir).filter(f => /^worship_\d{4}\.json$/.test(f)).sort()
let total = 0
for (const f of files) {
  const book = JSON.parse(readFileSync(join(dir, f), 'utf8'))
  const source = `${name} ${book.year}`
  const rows = (book.entries || []).filter(e => /^\d{4}-\d{2}-\d{2}$/.test(e.date || ''))
  const values = rows.map(e => {
    const data = { ...e, hymnal: book.hymnal }
    return `(${q(source)}, ${q(e.date)}, ${q(litKey(e.date))}, ${q(civilKey(e.date))}, ${q(e.occasion || '')}, ${q(JSON.stringify(data))}::jsonb)`
  })
  const sql = `begin;\ndelete from public.worship_refs where source = ${q(source)};\n` +
    (values.length ? `insert into public.worship_refs (source, date, lit_key, civil_key, occasion, data) values\n${values.join(',\n')};\n` : '') +
    'commit;\n'
  const file = join(tmp, `${book.year}.sql`)
  writeFileSync(file, sql)
  run(file)
  total += rows.length
  console.log(`${source}: ${rows.length}개`)
}
console.log(`모두 ${total}개 넣음`)
