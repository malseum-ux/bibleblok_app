// 바이블블록 회원 탈퇴 — 로그인한 본인의 계정을 지운다
// 1. 카카오로 가입했으면 카카오 연결 끊기 (KAKAO_ADMIN_KEY 가 있을 때)
// 2. Supabase 계정 삭제 (서비스 키 — 서버에서만 가능)
// Apple 로그인 연결 해제(토큰 취소)는 Apple 로그인을 켤 때(iOS·Mac 빌드 단계) 함께 넣는다.
// 사용자가 고른 저장 폴더의 파일은 사용자 기기에 있으므로 지우지 않는다.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const url = Deno.env.get('SUPABASE_URL') ?? ''
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') ?? '', {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  })
  const { data: { user } } = await userClient.auth.getUser()
  if (!user) return json({ error: '로그인이 필요합니다.' }, 401)

  const notes: string[] = []

  // 카카오 연결 끊기
  const kakao = user.identities?.find((i) => i.provider === 'kakao')
  const kakaoAdminKey = Deno.env.get('KAKAO_ADMIN_KEY')
  if (kakao) {
    if (kakaoAdminKey) {
      const res = await fetch('https://kapi.kakao.com/v1/user/unlink', {
        method: 'POST',
        headers: { Authorization: `KakaoAK ${kakaoAdminKey}`, 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ target_id_type: 'user_id', target_id: String(kakao.id) }),
      })
      if (!res.ok) notes.push(`kakao unlink ${res.status}`)
    } else {
      notes.push('kakao admin key missing')
    }
  }

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
  const { error } = await admin.auth.admin.deleteUser(user.id)
  if (error) return json({ error: error.message, notes }, 500)
  return json({ ok: true, notes })
})
