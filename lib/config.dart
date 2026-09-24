// Supabase (로그인·AI 서버·구독 확인) — 웹 바이블블록·워드블록과 같은 프로젝트
const kSupabaseUrl = 'https://pdrxuxrlwreqgiptzily.supabase.co';

// 공개(익명) 키 — 앱에 들어가도 되는 키. 데이터 보호는 로그인 확인·RLS 가 맡는다
const kSupabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBkcnh1eHJsd3JlcWdpcHR6aWx5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU5MjQzNjYsImV4cCI6MjEwMTUwMDM2Nn0.4RNPgQOWfyyg6fridnk5sxOtff17gyUWziXgLvhOOEc';

// AI 요청 주소 — 로그인한 사용자만 쓸 수 있는 Supabase 서버 함수 (supabase/functions/bibleblok-generate)
const kAiEndpoint = String.fromEnvironment('AI_ENDPOINT', defaultValue: '$kSupabaseUrl/functions/v1/bibleblok-generate');

// 회원 탈퇴 (supabase/functions/bibleblok-delete-account)
const kDeleteAccountEndpoint = '$kSupabaseUrl/functions/v1/bibleblok-delete-account';
