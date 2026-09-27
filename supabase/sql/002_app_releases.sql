-- 앱 최신 버전 — 설정 화면의 "업데이트 확인" 이 읽는다 (누구나 읽기만 가능)
-- 새 버전을 내면 해당 기기의 version(과 url)만 바꾸면 된다.
--   platform: macos | windows | ios | android  (웹은 배포 파일을 직접 비교해서 이 표를 쓰지 않는다)
--   url: 새 버전을 받는 곳 (Mac·Windows 다운로드 주소, iPhone·Android 스토어 주소). 비어 있으면 버튼 없이 안내만
create table if not exists public.app_releases (
  app text not null,
  platform text not null,
  version text not null,
  url text,
  notes text,
  updated_at timestamptz not null default now(),
  primary key (app, platform)
);

alter table public.app_releases enable row level security;

drop policy if exists "app_releases readable by anyone" on public.app_releases;
create policy "app_releases readable by anyone" on public.app_releases for select using (true);

insert into public.app_releases (app, platform, version) values
  ('bibleblok', 'macos', '1.0.0'),
  ('bibleblok', 'windows', '1.0.0'),
  ('bibleblok', 'ios', '1.0.0'),
  ('bibleblok', 'android', '1.0.0')
on conflict (app, platform) do nothing;
