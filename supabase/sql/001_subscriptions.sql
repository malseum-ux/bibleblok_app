-- 구독 표 — 바이블블록·워드블록 공용 (같은 Supabase 프로젝트 pdrx)
-- 정책: 바이블블록 구독 → 워드블록 포함 / 워드블록 구독 → 바이블블록 미포함
--   바이블블록 사용 가능: app = 'bibleblok' AND 사용 중
--   워드블록 사용 가능:   app IN ('bibleblok', 'wordblok') AND 사용 중
-- 사용 중 = status = 'active' AND (expires_at IS NULL OR expires_at > now())
--
-- 사용자는 자기 구독을 "읽기만" 할 수 있다. 쓰기는 서버(결제 연동·관리자)만 한다.
-- Supabase → SQL Editor 에서 실행하세요. (표가 이미 있으면 아무것도 바꾸지 않습니다)

create table if not exists public.subscriptions (
  user_id    uuid not null references auth.users(id) on delete cascade,
  app        text not null check (app in ('bibleblok', 'wordblok')),
  status     text not null default 'active' check (status in ('active', 'expired')),
  expires_at timestamptz,
  source     text not null default 'manual' check (source in ('manual', 'revenuecat', 'appstore', 'playstore')),
  updated_at timestamptz not null default now(),
  primary key (user_id, app)
);

alter table public.subscriptions enable row level security;

drop policy if exists "subscriptions_read_own" on public.subscriptions;
create policy "subscriptions_read_own" on public.subscriptions
  for select using (auth.uid() = user_id);

-- 수동으로 구독을 넣을 때 (예: 테스터) — 이메일만 바꿔서 실행
-- insert into public.subscriptions (user_id, app, status, source)
-- select id, 'bibleblok', 'active', 'manual' from auth.users where email = 'someone@example.com'
-- on conflict (user_id, app) do update set status = 'active', updated_at = now();
