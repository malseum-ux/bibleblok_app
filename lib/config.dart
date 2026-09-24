// AI 요청을 보낼 주소 — 웹 bibleblok 의 Vercel 서버(api/generate.ts)와 같은 DeepSeek 중계
// 4단계(로그인·AI 서버 잠금)에서 Supabase 서버 함수로 바꾼다.
const kAiEndpoint = String.fromEnvironment('AI_ENDPOINT', defaultValue: '');

// Supabase (로그인·구독 확인 전용) — 웹·워드블록과 같은 프로젝트
const kSupabaseUrl = 'https://pdrxuxrlwreqgiptzily.supabase.co';
