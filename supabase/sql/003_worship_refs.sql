-- 예배인도 참고 자료 — 선생님 소장 예배 자료집에서 뽑은 주일별 성구·찬송·기도문
-- 비공개: RLS 를 켜고 정책을 두지 않아 앱(익명·로그인 키)에서는 읽을 수 없다. 서버 함수(service role)만 읽는다
create table if not exists public.worship_refs (
  id bigserial primary key,
  source text not null,          -- 자료 이름과 해 (예: 복음적인 예배와 설교를 위하여 2013)
  date date not null,            -- 그 자료의 예배 날짜
  lit_key text not null,         -- 교회력 위치 (예: advent-1, lent-3, pent-12)
  civil_key text not null,       -- 달력 위치 (예: 11-sun3, 12-31)
  occasion text,                 -- 자료에 적힌 절기·주일 이름
  data jsonb not null            -- 성구·기도문·찬송 등
);
create index if not exists worship_refs_lit on public.worship_refs (lit_key);
create index if not exists worship_refs_civil on public.worship_refs (civil_key);
alter table public.worship_refs enable row level security;
