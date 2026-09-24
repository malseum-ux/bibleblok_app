// 웹(bibleblok/src/claude.js)의 프롬프트 부분과 같은 내용
// 요청 보내기(streamCompletion)는 ai.dart 에 있다. 여기서는 프롬프트 글만 만든다.
// 각 generateXxx 함수는 같은 이름의 buildXxxPrompt 로 글을 만든 뒤 streamCompletion 을 부른다.
import 'ai.dart';
import 'hymns.dart';
import 'worship_verses.dart';

/// 생성 중 지금까지 받은 전체 글을 받는 콜백 (웹 onChunk)
typedef ChunkCallback = void Function(String full);

/// 단계별 연구 내용 한 칸 (웹 stepsData 의 { label, content })
typedef StepData = ({String label, String content});

/// 프롬프트와 시스템 추가 지시 한 묶음
typedef BuiltPrompt = ({String prompt, String systemExtra});

/// 단계 안의 지시항목 하나 (웹 { key, label, text })
class StepItem {
  final String key;
  final String label;
  final String text;
  const StepItem({required this.key, required this.label, required this.text});
}

// ── 작은 도우미 ──────────────────────────────────────────────

/// JS 의 `a || b` (빈 글이나 null 이면 b)
String _or(String? v, String fallback) => (v == null || v.isEmpty) ? fallback : v;

/// JS 에서 글이 참(truthy)인지 — null 도 빈 글도 아님
bool _has(String? v) => v != null && v.isNotEmpty;

String _langName(String lang) => lang == 'ko' ? '한국어' : 'English';

/// JS `s.slice(-n)` — 뒤에서 n 글자
String _lastChars(String s, int n) => s.length > n ? s.substring(s.length - n) : s;

/// JS `s.slice(0, n)` — 앞에서 n 글자
String _firstChars(String s, int n) => s.length > n ? s.substring(0, n) : s;

const _citationPolicyEn = '''\n[Scripture Citation Policy]
- Direct Bible quotations must not exceed 500 verses total per document
- Always include the version abbreviation after each quote (e.g., ESV, NIV)
- Do not reproduce entire chapters verbatim
- Paraphrase or summarize where extended passages are needed''';

/// 영어일 때만 성경 인용 정책을 덧붙인다
String withCitationPolicy(String prompt, String lang) {
  if (lang != 'en') return prompt;
  return prompt + _citationPolicyEn;
}

/// 설교 단계별 지시항목 (웹 SERMON_STEP_ITEMS)
const Map<String, List<StepItem>> sermonStepItems = {
  'narrative': [
    StepItem(key: 'context', label: '전후 문맥', text: '- 본문의 전후 문맥'),
    StepItem(key: 'position', label: '위치와 역할', text: '- 해당 성경책에서의 위치와 역할'),
    StepItem(key: 'structure', label: '서사 구조', text: '- 서사 구조적 의미와 흐름'),
    StepItem(key: 'canonical', label: '정경 신학', text: '- 정경 전체에서의 신학적 위치'),
  ],
  'original': [
    StepItem(key: 'source', label: '원어 텍스트 기반', text: '- 구약이면 BHS(히브리어), 신약이면 NA28(헬라어)와 LXX 기반'),
    StepItem(key: 'parsing', label: '주요구절 파싱', text: '- 본문 주요 구절의 문법적 파싱 (동사의 시제·법·태·인칭·수, 명사의 격·수·성 등 원어 문법 구조 분석)'),
    StepItem(key: 'words', label: '주요 단어 분석', text: '- 주요 단어와 문구의 원어 분석'),
    StepItem(key: 'usage', label: '신구약 용례', text: '- 신구약 성경에서의 용례 비교'),
    StepItem(key: 'meaning', label: '신학적 함의', text: '- 어근과 의미의 신학적 함의'),
  ],
  'message': [
    StepItem(key: 'christology', label: '기독론적 관점', text: '- 기독론적 관점: 이 본문이 그리스도를 어떻게 가리키는지, 대표적인 신학자들(칼빈, 루터, 바르트, 라이트 등)과 설교가들이 이 본문을 기독론적으로 어떻게 해석해 왔는지 구체적으로 설명'),
    StepItem(key: 'original_audience', label: '최초 청중 메시지', text: '- 최초 청중 메시지: 본문이 원래 청중에게 전달하려 한 메시지'),
    StepItem(key: 'today', label: '오늘날 메시지', text: '- 오늘날 메시지: 오늘날 교회와 신자에게 전하는 메시지'),
  ],
  'lesson': [
    StepItem(key: 'god', label: '하나님 성품', text: '- 하나님의 성품과 사역에 대한 교훈'),
    StepItem(key: 'jesus', label: '예수님의 실천적 모범', text: '- 예수님이 이 본문에서 보여주시는 실천적 모범'),
    StepItem(key: 'human', label: '인간 본성', text: '- 인간의 본성과 반응에 대한 교훈'),
    StepItem(key: 'lessons', label: '본문의 교훈', text: '- 본문에서 도출할 수 있는 핵심 교훈 5가지 (각 교훈을 간결하게 제목으로 제시하고 설명)'),
  ],
  'text_study': [
    StepItem(key: 'main_theme', label: '주요 신학적 주제', text: '- 본문의 주요 신학적 주제'),
    StepItem(key: 'history', label: '신학적 해석 역사', text: '- 신학적 해석 역사: 교부, 중세, 개혁신학, 근대 주요 신학자들이 이 본문을 어떻게 해석해 왔는지 구체적으로 설명'),
    StepItem(key: 'modern', label: '현대 신학자 해석', text: '- 현대 주요 신학자들의 해석: 대표적인 현대 신학자들이 이 본문을 어떻게 해석하는지 구체적으로 설명'),
    StepItem(key: 'rabbi', label: '정통 랍비 해석', text: '- 정통 랍비 해석: 유대교 정통 랍비 전통에서 이 본문(또는 해당 구약 본문)을 어떻게 해석해 왔는지 설명'),
  ],
  'research': [
    StepItem(key: 'literary', label: '문학적 관점', text: '- 문학적 관점: 문학 비평가의 틀로 본문의 장르, 문체, 서사 구조, 수사법이 본문 의미에 어떻게 기여하는지 해석'),
    StepItem(key: 'historical', label: '역사적 관점', text: '- 역사적 관점: 역사가의 해석학적 틀로 본문의 사건과 의미를 해석 (고고학적 사실 규명이 아닌 역사적 해석학)'),
    StepItem(key: 'philosophical', label: '철학적 관점', text: '- 철학적 관점: 철학자의 틀로 본문이 담고 있는 세계관, 존재론, 윤리적 함의를 해석'),
    StepItem(key: 'sociological', label: '사회학적 관점', text: '- 사회학적 관점: 사회학자의 틀로 당시 사회 구조, 권력 관계, 문화적 맥락이 본문 의미에 미치는 영향을 해석'),
    StepItem(key: 'psychological', label: '심리학적 관점', text: '- 심리학적 관점: 심리학자의 틀로 본문 인물의 내면 동기, 감정, 행동 패턴을 해석'),
  ],
  'illustration': [
    StepItem(key: 'biblical', label: '성경 예화', text: '- 성경 예화: 본문과 연결되는 구약 예화 2개, 신약 예화 2개 (각 예화마다 본문과 연결되는 이유 설명)'),
    StepItem(key: 'historical', label: '역사적 사건', text: '- 역사적 사건: 본문과 연결되는 국내 역사적 사건 2개, 국외 역사적 사건 2개 (각 사건마다 본문과 연결되는 이유 설명)'),
    StepItem(key: 'literary', label: '문학 예화', text: '- 문학 예화: 본문과 연결되는 국내 문학 작품 예화 2개, 국외 문학 작품 예화 2개 (각 예화마다 본문과 연결되는 이유 설명)'),
    StepItem(key: 'modern', label: '현대 언론 예화', text: '- 현대 언론 예화: 레거시 언론에 보도된 사건사고에서 볼 수 있는 현대인의 삶 예화 2개 (각 예화마다 본문과 연결되는 이유 설명)'),
  ],
  'hymns': [
    StepItem(key: 'before_hymn', label: '설교 전 찬송가', text: '- 설교 전 찬송가 1곡 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 선택 이유)'),
    StepItem(key: 'before_ccm', label: '설교 전 CCM', text: '- 설교 전 CCM 1곡 (제목, 아티스트, 선택 이유)'),
    StepItem(key: 'after_hymn', label: '설교 후 찬송가', text: '- 설교 후 찬송가 1곡 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 선택 이유)'),
    StepItem(key: 'after_ccm', label: '설교 후 CCM', text: '- 설교 후 CCM 1곡 (제목, 아티스트, 선택 이유)'),
    StepItem(key: 'explanation', label: '연결 설명', text: '- 각 곡이 본문 메시지와 어떻게 연결되는지, 예배 흐름에서 어떤 역할을 하는지 설명'),
  ],
  'application': [
    StepItem(key: 'personal', label: '개인 적용', text: '- 개인 적용: 지금까지의 해설(원어, 역사적 배경, 신학적 의미, 교훈)을 바탕으로 개인 신앙 생활에 구체적으로 어떻게 적용할 수 있는지 제시'),
    StepItem(key: 'community', label: '공동체 적용', text: '- 공동체 적용: 지금까지의 해설을 바탕으로 교회 공동체가 함께 실천하거나 변화해야 할 내용을 구체적으로 제시'),
    StepItem(key: 'social', label: '사회 적용', text: '- 사회 적용: 지금까지의 해설을 바탕으로 사회와 세상을 향해 이 본문이 요구하는 실천을 구체적으로 제시'),
    StepItem(key: 'practical', label: '구체적 실천', text: '- 구체적 실천: 지금까지의 해설에서 도출한 이번 주 바로 실천할 수 있는 구체적 행동 3~5가지 제시'),
  ],
  'deep_questions': [
    StepItem(key: 'inductive', label: '귀납법적 질문', text: '- 귀납법적 질문과 해설: 본문의 구체적 사실과 관찰에서 출발해 교훈을 도출하는 질문 3~5개와 각 질문에 대한 해설'),
    StepItem(key: 'deductive', label: '연역법적 질문', text: '- 연역법적 질문과 해설: 교훈의 핵심 명제에서 출발해 구체적 삶의 상황에 적용하는 질문 3~5개와 각 질문에 대한 해설'),
    StepItem(key: 'dialectical', label: '변증법적 질문', text: '- 변증법적 질문과 해설(정반합): 교훈에 대한 긍정 명제(정)와 그에 맞서는 반론(반), 그 긴장을 통합하는 새로운 이해(합)로 구성된 질문 3~5개와 각 질문에 대한 해설'),
  ],
};

/// 예배 단계별 지시항목 (웹 WORSHIP_STEP_ITEMS)
const Map<String, List<StepItem>> worshipStepItems = {
  'call_verse': [
    StepItem(key: 'verse', label: '추천 구절', text: '- 예배의 부름으로 적합한 구절 1~2개 추천 (장절 + 본문 전체)'),
    StepItem(key: 'lectionary', label: '성경정과 참조', text: '- 해당 주일의 성서정과 본문을 참조하여 구절 선택'),
    StepItem(key: 'calendar', label: '교회력 참조', text: '- 현재 교회력 절기(대강절/성탄절/주현절/사순절/부활절/성령강림절 등)에 맞게 선택'),
    StepItem(key: 'season', label: '계절 참조', text: '- 자연 계절(봄/여름/가을/겨울)의 분위기를 반영하여 선택'),
  ],
  'call_prayer': [
    StepItem(key: 'lectionary', label: '성경정과 참조', text: '- 해당 주일의 성서정과 본문을 기도문에 반영'),
    StepItem(key: 'calendar', label: '교회력 참조', text: '- 현재 교회력 절기에 맞는 기도문 작성'),
    StepItem(key: 'season', label: '계절 참조', text: '- 자연 계절 분위기를 기도문에 담아 작성'),
  ],
  'confession': [],
  'forgiveness': [],
  'worship_prayer': [],
  'offering': [],
  'responsive_reading': [
    StepItem(key: 'lectionary', label: '성경정과 참조', text: '- 해당 주일의 성서정과 본문과 연결되는 교독문 선택'),
    StepItem(key: 'calendar', label: '교회력 참조', text: '- 현재 교회력 절기에 맞는 교독문 선택'),
    StepItem(key: 'full', label: '교독문 전문', text: '- 선택한 교독문 전문 (인도자/회중 구분하여 작성)'),
  ],
  'opening_hymns': [
    StepItem(key: 'hymnal', label: '찬송가', text: '- 찬송가에서 예배를 여는 곡 1~2곡 추천 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 선택 이유)'),
    StepItem(key: 'ccm', label: 'CCM', text: '- 예배를 여는 CCM 1~2곡 추천 (제목, 아티스트, 선택 이유)'),
  ],
  'pre_sermon_hymns': [
    StepItem(key: 'hymnal', label: '찬송가', text: '- 찬송가에서 설교 전 곡 1~2곡 추천 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 선택 이유)'),
    StepItem(key: 'ccm', label: 'CCM', text: '- 설교 전 CCM 1~2곡 추천 (제목, 아티스트, 선택 이유)'),
  ],
  'post_sermon_hymns': [
    StepItem(key: 'hymnal', label: '찬송가', text: '- 찬송가에서 설교 후 응답/결단 곡 1~2곡 추천 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 선택 이유)'),
    StepItem(key: 'ccm', label: 'CCM', text: '- 설교 후 응답/결단을 위한 CCM 1~2곡 추천 (제목, 아티스트, 선택 이유)'),
  ],
  'benediction': [],
  'sending': [
    StepItem(key: 'verse', label: '추천 구절', text: '- 파송에 어울리는 성경구절 1개 추천 (장절 + 본문)'),
    StepItem(key: 'declaration', label: '파송 선언문', text: '- 세상으로 나아가는 파송 선언문 (3~5줄)'),
  ],
};

/// 새벽 단계별 지시항목 (웹 DAWN_STEP_ITEMS)
const Map<String, List<StepItem>> dawnStepItems = {
  'exposition': [
    StepItem(key: 'intro', label: '본문 소개/배경', text: '- 본문의 역사적·문학적 배경을 간략히 서술'),
    StepItem(key: 'words', label: '주요 단어·문구', text: '- 본문의 주요 단어와 문구를 해설 (신학적·언어적 의미 포함)'),
    StepItem(key: 'meaning', label: '본문 주요 의미', text: '- 본문이 전달하는 주요 의미와 신학적 핵심을 해설'),
    StepItem(key: 'message', label: '핵심 내용 해설', text: '- 본문 전체를 종합하여 해설하듯 풀어서 서술'),
  ],
  'core_message': [
    StepItem(key: 'proclamation', label: '핵심 메시지', text: '- 이 본문이 전하는 단 하나의 핵심 메시지를 명확하게 서술'),
    StepItem(key: 'points', label: '핵심 포인트', text: '- 그 메시지를 뒷받침하는 핵심 포인트 2~3가지를 설명하듯 서술'),
  ],
  'meditation': [
    StepItem(key: 'questions', label: '묵상 질문', text: '- 깊이 생각해 볼 묵상 질문 2~3개 (질문 후 짧은 해설 포함)'),
    StepItem(key: 'verse', label: '핵심 구절', text: '- 반복해서 되새길 핵심 구절 1개와 그 의미 서술'),
  ],
  'application': [
    StepItem(key: 'connection', label: '본문 연결', text: '- 이 실천적 교훈이 본문 어디에서 나오는지 먼저 설명'),
    StepItem(key: 'action', label: '실천 적용', text: '- 본문에서 이끌어낸 구체적인 실천적 교훈 (가정/직장/교회/이웃 중 한 영역)'),
  ],
  'prayer_topics': [
    StepItem(key: 'personal', label: '개인 기도', text: '- 개인 기도 (본문 말씀을 내 삶에 적용하는 기도)'),
    StepItem(key: 'church', label: '교회 기도', text: '- 교회 공동체를 위한 기도'),
    StepItem(key: 'nation', label: '나라와 이웃', text: '- 나라와 이웃을 위한 기도'),
  ],
  'hymn': [
    StepItem(key: 'hymnal', label: '찬송가 추천', text: '- 찬송가 1곡 (대한찬송가공회 2006년 발행, 총 645장 기준으로 번호, 제목, 이 본문과 연결되는 이유 2~3줄)'),
    StepItem(key: 'ccm', label: 'CCM 추천', text: '- CCM 1곡 (제목, 아티스트, 이 본문과 연결되는 이유 2~3줄)'),
  ],
};

// ── 셀 교재 ──────────────────────────────────────────────────

typedef _CellPromptFn = String Function(String passage, String? bible);

final Map<String, _CellPromptFn> _cellMaterialPrompts = {
  'sharing': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가입니다.
아래 성경 본문으로 "나눔 교재 — 삶으로 나누는 말씀"을 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[나눔 교재란]
신학 지식이 없어도 누구나 편하게 참여할 수 있는 소그룹 나눔 교재입니다.
본문을 분석하는 것이 목적이 아닙니다.
말씀 앞에서 내 삶을 꺼내놓고, 서로를 더 알아가는 것이 목적입니다.
45~60분 소그룹에 적합합니다.

[원칙]
1. 질문은 누구나 대답할 수 있어야 합니다. 신학 지식이 필요한 질문은 쓰지 마세요.
2. 삶의 경험에서 출발하세요. 본문 해석보다 "내 이야기"가 먼저 나오는 구조입니다.
3. 강요하지 않습니다. 모든 질문에 "나누고 싶은 분만 나눠주세요"가 전제됩니다.
4. 침묵도 존중받습니다. 대답하지 않는 것도 하나의 참여입니다.
5. 나눔 후 서로를 더 알게 되고 공동체가 깊어지는 방향으로 마무리합니다.

[절대 하지 말아야 할 것]
- 강의 투 문장 금지
- 정답이 정해진 유도 질문 금지
- 신학 용어, 원어, 교회 전문 용어 사용 금지
- "은혜", "축복", "감사" 등 뻔한 교회 언어 남발 금지
- 인도자 해설을 모든 섹션에서 같은 패턴으로 반복 금지

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.
해설은 별도 구분선 없이 각 섹션 직후에 작성하세요.''',

  'theological': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가이자 성경 신학자입니다.
아래 성경 본문으로 "신학적 교재 — 뿌리에서 열매까지"를 작성해 주세요.
A4 3~4매 분량(약 3,000~4,500자)으로 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[신학적 교재란]
본문을 신학적으로 깊이 탐구하되, 소그룹이 함께 발견하는 구조입니다.
강의가 아닌 탐구입니다. 인도자가 답을 주는 것이 아니라 함께 발견합니다.
90분 소그룹에 적합합니다.

[원어 표기 원칙]
히브리어 단어나 헬라어 단어를 언급할 때는 반드시 원어 문자를 직접 표기하고, 괄호 안에 한글 음가를 함께 표기하세요.
예시) 헬라어: λόγος (로고스), 히브리어: אֱלֹהִים (엘로힘)
신약이면 헬라어(NA28 기준), 구약이면 히브리어(BHS 기준)를 사용하세요.

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.
신학적 대화 섹션 해설에는 반드시 위험한 방향(이단적 결론, 극단적 해석)을 명시하세요.''',

  'gospel': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가이자 복음 중심 설교자입니다.
아래 성경 본문으로 "복음적 교재 — 그리스도 안에서"를 작성해 주세요.
A4 3~4매 분량(약 3,000~4,500자)으로 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[복음적 교재란]
이 본문이 어떻게 예수 그리스도를 가리키는지 발견하는 교재입니다.
율법이 아닌 은혜, 정죄가 아닌 구원의 렌즈로 본문을 읽습니다.
복음을 지식으로 배우는 것이 아니라, 내 삶 안에서 복음이 어떻게 살아있는지를 함께 나눕니다.
90분 소그룹에 적합합니다.

[구성 원칙]
1. 본문과 복음의 연결: 이 본문이 그리스도의 죽음·부활·은혜를 어떻게 예비하거나 가리키는지 드러내세요. 억지 연결은 금지.
2. 율법과 복음의 구분: 본문이 인간의 실패를 드러낸다면, 그 자리에 복음이 어떻게 임하는지를 보여주세요.
3. 은혜의 구체성: "은혜를 받아야 한다"가 아니라, 이 본문에서 은혜가 어떤 모습으로 나타나는지 구체적으로 제시하세요.
4. 삶 적용: 복음이 오늘 나의 삶 — 관계, 두려움, 실패, 희망 — 에 어떻게 들어오는지를 나눌 수 있는 질문으로 연결하세요.
5. 설교가 아닌 나눔: 인도자가 정답을 주는 강의가 아니라, 함께 복음을 발견하는 탐구 구조로 작성하세요.

[절대 하지 말아야 할 것]
- "더 노력해야 한다", "더 헌신해야 한다"는 율법적 결론 금지.
- 복음을 도덕 교훈으로 환원하는 것 금지.
- "우리가 이렇게 살면 복을 받는다"는 번영신학적 결론 금지.

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.
율법적 방향으로 흐를 수 있는 위험을 반드시 명시하세요.''',

  'literary': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가이자 문학 비평가입니다.
아래 성경 본문으로 "문학적 교재 — 이야기 속으로"를 작성해 주세요.
A4 3~4매 분량(약 3,000~4,500자)으로 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[문학적 교재란]
성경을 문학 작품으로 읽습니다. 문학적 기법과 서사 구조를 탐구하고,
등장인물의 심리와 동기를 발견하며, 이야기가 나에게 건네는 말을 듣습니다.
90분 소그룹에 적합합니다.

[중요 원칙]
- 문학적 관찰(섹션 3): 본문의 구조와 기법만 다룹니다. 인물의 심리와 동기는 다음 섹션에서 다룹니다.
- 등장인물 탐구(섹션 4): 인물의 내면에 집중합니다. 이야기 구조 반복 금지.
- 유사 인물 성경 연결: 자연스럽고 이해에 실질적 도움이 될 때만 포함. 없으면 완전히 생략.
- 등장인물이 없는 본문(시편·서신서): 화자/청중 분석으로 대체.

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.''',

  'psychological': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가이자 심리학적 통찰을 가진 목회자입니다.
아래 성경 본문으로 "심리학적 교재 — 말씀 앞에 나를 내려놓기"를 작성해 주세요.
A4 3~4매 분량(약 3,000~4,500자)으로 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[심리학적 교재란]
심리학은 도구입니다. 말씀을 섬기기 위한 도구이지, 말씀을 대체하지 않습니다.
본문을 통해 나의 내면을 비춰보고, 하나님의 은혜로 나아가는 것이 목적입니다.
90분 소그룹에 적합합니다.

[중요 원칙]
- 심리학 개념은 일상 언어로, 3분 안에 설명 가능한 분량으로 소개하세요.
- 모든 분석은 공감의 방식으로 — 판단이 아닌 이해를 목적으로.
- 성찰이 자기 정죄가 되지 않도록 하세요. 말씀은 정죄가 아닌 비춤입니다.
- 신뢰 수준별 질문: 처음 만나는 그룹용·신뢰가 쌓인 그룹용 두 가지를 모두 제공하세요.
- 전문 상담 연계: 심각한 트라우마가 드러날 경우를 위한 안내를 인도자 해설에 명시하세요.
- MBTI는 자연스러울 때만 포함. 어색하면 생략.
- 등장인물이 없는 본문(시편·서신서): 화자의 감정과 심리 분석으로 대체.

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.''',

  'communal': (passage, bible) => '''당신은 소그룹 나눔 교재 전문가이자 사회학적 통찰을 가진 목회자입니다.
아래 성경 본문으로 "공동체적 교재 — 함께 세상으로"를 작성해 주세요.
A4 3~4매 분량(약 3,000~4,500자)으로 작성해 주세요.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}

[공동체적 교재란]
사회학은 도구입니다. 말씀을 섬기기 위한 도구이지, 말씀을 대체하지 않습니다.
공동체의 구조와 권력 관계를 말씀의 빛으로 성찰하고, 세상으로 파송되는 것이 목적입니다.
90분 소그룹에 적합합니다.

[중요 원칙]
- 혐오·배제 표현 절대 금지. 특정 민족·성별·계층·장애에 대한 혐오 절대 금지.
- 특정 정당·정치인·이념을 지목하거나 지지하는 내용 절대 금지.
- 민주적 가치(인권, 평등, 연대, 비폭력, 소수자 보호)를 지향하세요.
- 혐오와 배제가 "연대"의 언어로 포장되어 들어오지 않도록 하세요.
- 사회 참여는 특정 정치 성향이 아닌 말씀의 원리에서 출발해야 합니다.
- 등장인물이 없는 본문(시편·예언서·서신서): 해당 공동체의 사회적 상황 분석으로 대체.

[인도자 해설 작성 기준]
각 섹션마다 인도자를 위한 해설을 작성하세요.
해설은 반드시 목적·이유·진행 팁을 포함하세요.
이 본문에서만 일어날 수 있는 반응과 상황을 예상해서 쓰세요.
정치적으로 민감한 방향으로 흐를 수 있는 위험을 반드시 명시하세요.''',
};

BuiltPrompt buildCellMaterialPrompt(String? passage, String? bible, String lang, String stepKey,
    [String customText = '', String userKeyword = '', String sermonContext = '', String memory = '']) {
  final promptFn = _cellMaterialPrompts[stepKey];
  if (promptFn == null) throw Exception('Unknown cell step key: $stepKey');
  var prompt = withCitationPolicy(promptFn(passage ?? '', bible), lang);
  if (customText.isNotEmpty) prompt += '\n\n[구성 지시항목 — 아래 항목을 반드시 포함하여 작성하세요]\n$customText';
  if (sermonContext.isNotEmpty) {
    prompt +=
        '\n\n[설교 연구 참고 자료]\n아래는 같은 본문으로 작성된 설교 연구 내용입니다. 이 자료를 충분히 반영하여 교재를 작성해 주세요. 설교자의 본문 이해와 신학적 관점, 강조점을 교재 곳곳에 녹여주세요.\n\n$sermonContext';
  }
  if (memory.isNotEmpty) prompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) prompt += '\n\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  return (prompt: prompt, systemExtra: '');
}

Future<String> generateCellMaterial(String? passage, String? bible, String lang, String stepKey, ChunkCallback? onChunk,
    [String customText = '', String userKeyword = '', String sermonContext = '', String memory = '']) {
  final b = buildCellMaterialPrompt(passage, bible, lang, stepKey, customText, userKeyword, sermonContext, memory);
  return streamCompletion(b.prompt, onChunk);
}

/// 선택된 항목(없으면 전부)의 text 를 줄바꿈으로 잇는다
String buildItems(List<StepItem> items, List<String>? selectedKeys) {
  final list = selectedKeys != null ? items.where((i) => selectedKeys.contains(i.key)) : items;
  return list.map((i) => i.text).where((t) => t.isNotEmpty).join('\n');
}

// ── 설교 단계 ────────────────────────────────────────────────

typedef _SermonPromptFn = String Function(String passage, String lang, String? bible, List<String>? selectedKeys);

final Map<String, _SermonPromptFn> _sermonStepPrompts = {
  'narrative': (passage, lang, bible, selectedKeys) => '''\n당신은 성경 신학자입니다. 다음 성경 본문에 대해 서사적 관점에서 해설해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

다음을 포함하세요:
${buildItems(sermonStepItems['narrative']!, selectedKeys)}
''',
  'text_study': (passage, lang, bible, selectedKeys) => '''\n당신은 성경 신학 전문가입니다. 다음 본문을 신학적으로 깊이 연구해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

다음을 포함하세요:
${buildItems(sermonStepItems['text_study']!, selectedKeys)}
''',
  'original': (passage, lang, bible, selectedKeys) => '''\n당신은 성경 원어 전문가입니다. 다음 본문을 원어로 해설해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

[원어 표기 원칙]
히브리어 단어나 헬라어 단어를 언급할 때는 반드시 원어 문자를 직접 표기하고, 괄호 안에 한글 음가를 함께 표기하세요.
예시) 히브리어: אֱלֹהִים (엘로힘), 헬라어: λόγος (로고스)
원어 문자 없이 한글 설명만 쓰지 마세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

다음을 포함하세요:
${buildItems(sermonStepItems['original']!, selectedKeys)}
''',
  'message': (passage, lang, bible, selectedKeys) => '''\n앞서 분석한 내용을 바탕으로 이 본문이 전하는 핵심 메시지를 정리해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

${buildItems(sermonStepItems['message']!, selectedKeys)}
''',
  'lesson': (passage, lang, bible, selectedKeys) => '''\n이 본문에서 배울 수 있는 신앙적 교훈을 정리해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

${buildItems(sermonStepItems['lesson']!, selectedKeys)}
''',
  'research': (passage, lang, bible, selectedKeys) => '''\n이 본문을 다양한 학문적 관점으로 확장 연구해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

각 관점은 해당 분야 전문가(문학 비평가, 역사가, 철학자, 사회학자, 심리학자)가 실제로 사용하는 분석 틀과 개념을 활용하여, 그 관점에서 본문이 어떤 의미를 갖는지 해석하세요. 단순한 배경 나열이 아니라 전문가적 해석이어야 합니다.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

다음 관점을 포함하세요:
${buildItems(sermonStepItems['research']!, selectedKeys)}
''',
  'illustration': (passage, lang, bible, selectedKeys) => '''\n당신은 설교 전문가입니다. 다음 본문의 메시지를 효과적으로 전달할 수 있는 예화를 제시해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

다음을 포함하세요:
${buildItems(sermonStepItems['illustration']!, selectedKeys)}
''',
  'hymns': (passage, lang, bible, selectedKeys) => '''\n당신은 교회 음악 전문가입니다. 다음 설교 본문의 메시지에 어울리는 찬송과 CCM을 선별해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}
찬송가 기준: 대한찬송가공회 2006년 발행 찬송가 (총 645장)

[대한찬송가공회 찬송가 전체 목록 - 반드시 이 목록의 번호와 제목을 그대로 사용하세요]
${getHymnListText()}

다음을 포함하세요:
${buildItems(sermonStepItems['hymns']!, selectedKeys)}
''',
  'application': (passage, lang, bible, selectedKeys) => '''\n지금까지의 해설을 종합하여 오늘날 삶에 적용하는 내용을 작성해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

${buildItems(sermonStepItems['application']!, selectedKeys)}
''',
  'deep_questions': (passage, lang, bible, selectedKeys) => '''\n당신은 설교학 및 성경 교육 전문가입니다. 다음 본문의 교훈을 회중이 스스로 발견하고 깊이 내면화할 수 있도록 세 가지 논리적 방식의 질문과 해설을 작성해 주세요.
A4 용지 3~4매 분량(약 2,500~4,000자)으로 상세하게 작성해 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

${buildItems(sermonStepItems['deep_questions']!, selectedKeys)}
''',
};

/// 웹 SERMON_STEP_PROMPTS_WITH_EMPHASIS — 모든 단계가 같은 방식으로 강조 주제를 덧붙인다
String? _sermonStepPromptWithEmphasis(
    String stepKey, String passage, String? emphasis, String lang, String? bible, List<String>? selectedKeys) {
  final fn = _sermonStepPrompts[stepKey];
  if (fn == null) return null;
  return fn(passage, lang, bible, selectedKeys) + (_has(emphasis) ? '\n\n설교자가 강조하고 싶은 주제: $emphasis' : '');
}

BuiltPrompt buildSermonStepPrompt(String stepKey, String? passage, String? emphasis, String lang, String? bible,
    String? seriesCtx,
    [List<String>? selectedItems, String userKeyword = '', String customText = '', String memory = '']) {
  final prompt = _sermonStepPromptWithEmphasis(stepKey, passage ?? '', emphasis, lang, bible, selectedItems);
  if (prompt == null) throw Exception('Unknown sermon step key: $stepKey');
  var fullPrompt = _has(seriesCtx)
      ? '$prompt\n\n$seriesCtx\n\n[강해설교 연속성 지침]\n- 위 이전 설교들의 본문 흐름과 신학적 주제를 반드시 파악하세요.\n- 이번 본문이 시리즈 전체에서 어떤 위치에 있는지 의식하며 작성하세요.\n- 이전 설교에서 다룬 내용을 반복하지 말고, 자연스럽게 그 위에 쌓아가세요.\n- 회중이 앞 설교의 흐름을 기억하며 이번 말씀을 들을 수 있도록 연결 고리를 살려 주세요.'
      : prompt;
  fullPrompt +=
      '\n\n[문체 지침]\n모든 내용은 "~이다", "~한다" 형식의 평서체(이다체)로 작성하세요. "~입니다", "~합니다" 등의 존댓말은 사용하지 마세요.\n\n[중복 지양 지침]\n이 결과는 설교 준비의 여러 단계 중 하나입니다. 본문 소개나 배경 설명을 서론으로 반복하지 마세요. 이 단계 고유의 내용에 바로 집중하여 작성하세요.';
  fullPrompt = withCitationPolicy(fullPrompt, lang);
  if (customText.isNotEmpty) fullPrompt += '\n$customText';
  if (memory.isNotEmpty) fullPrompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) fullPrompt += '\n\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  return (prompt: fullPrompt, systemExtra: '');
}

Future<String> generateSermonStep(String stepKey, String? passage, String? emphasis, String lang, String? bible,
    String? seriesCtx, ChunkCallback? onChunk,
    [List<String>? selectedItems, String userKeyword = '', String customText = '', String memory = '']) {
  final b = buildSermonStepPrompt(
      stepKey, passage, emphasis, lang, bible, seriesCtx, selectedItems, userKeyword, customText, memory);
  return streamCompletion(b.prompt, onChunk);
}

// ── 예배 단계 ────────────────────────────────────────────────

typedef _WorshipPromptFn = String Function(
    String date, String? season, String? lectionary, String lang, String? bible, List<String>? selectedKeys);

String _worshipHeader(String? date, String? season, String? lectionary, String lang, String? bible) =>
    '날짜: ${date ?? ''} | 절기: ${_or(season, '일반 주일')} | 성서정과: ${_or(lectionary, '미지정')}\n'
    '번역본: ${_or(bible, '개역개정성경')} | 언어: ${_langName(lang)}';

final Map<String, _WorshipPromptFn> _worshipStepPrompts = {
  'call_verse': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[예배의 부름 성경구절]
${buildItems(worshipStepItems['call_verse']!, selectedKeys)}

[참고 구절 DB — 아래 목록에서 절기와 성서정과에 가장 어울리는 구절을 우선 선택하세요]
${getRandomVerseText(callToWorshipVerses)}

구절 선택 원칙:
- 위 DB 목록을 우선 참고하되, 더 적합한 구절이 있으면 사용할 수 있습니다.
- 시편 100편, 시편 95:1-6, 시편 150편, 요한복음 4:24처럼 지나치게 자주 반복되는 구절은 피하세요.
- 선택한 구절이 이 날짜·절기에 어울리는 이유를 한 줄로 설명하세요.
''',
  'call_prayer': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[예배의 부름 기도문]
절기 분위기를 담아 회중을 예배로 부르는 기도문을 작성해 주세요. (15~22줄 분량)
진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 기도문 본문만 작성하세요.
기도문 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺으세요.
''',
  'confession': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[참회의 기도문]
해당 절기에 맞는 참회의 기도문을 작성해 주세요. (15~22줄 분량)
말과 생각과 행동, 그리고 마땅히 해야 할 일을 하지 않은 태만까지, 구체적인 죄의 영역을 짚어 주세요.
단, 특정 개인이나 상황에 국한되지 않고 누구나 공감할 수 있는 일반적인 언어로 작성하세요.
삶의 반성과 진실한 회개의 내용이 담기도록 하세요.
진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 기도문 본문만 작성하세요.
기도문 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺으세요.
''',
  'forgiveness': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[용서의 선언 성경구절]
위 날짜·절기·성서정과와 어울리는 하나님의 용서와 사죄를 선언하는 성경구절을 3~5개 제시해 주세요.

[참고 구절 DB — 아래 목록에서 절기에 가장 어울리는 구절을 우선 선택하세요]
${getRandomVerseText(forgivenessVerses)}

각 구절마다 반드시 다음 형식을 모두 채워 작성하세요. 구절 전문을 생략하거나 요약하지 마세요:

구절 참조 (예: 요한일서 1:9)
구절 전문 — ${_or(bible, '개역개정성경')} 번역으로 한 글자도 빠짐없이 직접 인용
→ 이 구절이 용서의 선언으로 적합한 이유 한 줄

위 DB 목록을 우선 참고하되, 구약과 신약을 골고루 포함하고 요한일서 1:9·시편 103:12처럼 매주 반복되는 구절은 피하세요.
${buildItems(worshipStepItems['forgiveness']!, selectedKeys)}
''',
  'worship_prayer': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[예배를 위한 기도문]
다음 순서로 구성된 기도문을 45~60줄 분량으로 작성해 주세요.
1. 찬양 - 하나님의 성품과 위대하심을 높임
2. 감사 - 절기와 삶 속에서 베푸신 은혜에 감사
3. 회개 - 말씀 앞에 나아가기 전 죄를 고백하고 용서를 구함
4. 중보 - 국가와 지도자, 사회의 연약한 이웃, 교회와 오늘의 예배를 위해 기도
5. 간구 - 각 가정과 성도 개인의 필요를 위해 기도
진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 기도문 본문만 작성하세요.
기도문 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺으세요.
''',
  'offering': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[봉헌기도문]
헌금의 감사와 절기 정신을 담은 봉헌기도문을 작성해 주세요. (12~18줄 분량)
진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 기도문 본문만 작성하세요.
기도문 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺으세요.
''',
  'responsive_reading': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[교독문]
반드시 찬송가공회(한국찬송가공회)에서 발행한 찬송가 뒤에 수록된 교독문만을 참고하세요.
${buildItems(worshipStepItems['responsive_reading']!, selectedKeys)}
''',
  'opening_hymns': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[대한찬송가공회 찬송가 전체 목록 - 반드시 이 목록의 번호와 제목을 그대로 사용하세요]
${getHymnListText()}

[예배를 여는 찬양]
예배를 시작하며 회중의 마음을 하나님께 향하게 하는 찬양을 추천해 주세요.
${buildItems(worshipStepItems['opening_hymns']!, selectedKeys)}
''',
  'pre_sermon_hymns': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[대한찬송가공회 찬송가 전체 목록 - 반드시 이 목록의 번호와 제목을 그대로 사용하세요]
${getHymnListText()}

[설교전찬양]
설교를 앞두고 회중이 말씀을 받을 준비를 하도록 돕는 찬양을 추천해 주세요.
${buildItems(worshipStepItems['pre_sermon_hymns']!, selectedKeys)}
''',
  'post_sermon_hymns': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[대한찬송가공회 찬송가 전체 목록 - 반드시 이 목록의 번호와 제목을 그대로 사용하세요]
${getHymnListText()}

[설교후찬양]
설교 후 회중이 말씀에 응답하고 결단하도록 돕는 찬양을 추천해 주세요.
${buildItems(worshipStepItems['post_sermon_hymns']!, selectedKeys)}
''',
  'benediction': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 바로 사용할 수 있게 작성해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[축도]
다음 형식을 반드시 따르세요:
"주 예수 그리스도의 은혜와, [절기/말씀에 담긴 하나님의 성품]하나님의 사랑과, [절기/예배 흐름에 어울리는 표현]성령의 위로(교통)하심이 [오늘 이 자리에 모인/예배드린] 성도 위에 함께 하시기를 축원하노라."
삼위 각각의 수식어를 절기와 오늘 말씀에 어울리게 채워 주세요. (전체 5~8줄 분량)
진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 축도문 본문만 작성하세요.
''',
  'sending': (date, season, lectionary, lang, bible, selectedKeys) => '''\n예배 인도자를 위한 실용적인 제안입니다. 간결하게 답해 주세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[파송의 말씀]
${buildItems(worshipStepItems['sending']!, selectedKeys)}
''',
};

// ── 새벽 단계 ────────────────────────────────────────────────

typedef _DawnPromptFn = String Function(
    String passage, String lang, String? bible, String? seriesCtx, List<String>? selectedKeys);

String _seriesLine(String? seriesCtx) => _has(seriesCtx) ? '\n$seriesCtx' : '';

final Map<String, _DawnPromptFn> _dawnStepPrompts = {
  'exposition': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n아래 본문을 해설하는 글을 작성하세요.
문체: "~이다", "~한다", "~된다" 서술체만 사용. "사랑하는 여러분", "~해 봅시다" 등 구어체·청중 호칭 절대 금지.
구조: 아래 각 항목을 번호(1. 2. 3.)로 시작하고, 항목 사이에 반드시 빈 줄을 한 줄 넣어 구분하세요.
분량: 약 1,800~2,500자.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}
언어: ${_langName(lang)}
${_seriesLine(seriesCtx)}

${buildItems(dawnStepItems['exposition']!, selectedKeys)}
''',
  'core_message': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n이 본문의 핵심 메시지를 해설하는 글을 작성하세요.
문체: "~이다", "~한다" 서술체만 사용. "사랑하는 여러분", "~해 봅시다" 등 구어체·청중 호칭 절대 금지.
구조: 아래 각 항목을 번호(1. 2. 3.)로 시작하고, 항목 사이에 반드시 빈 줄을 한 줄 넣어 구분하세요.
분량: 약 900~1,200자.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}
언어: ${_langName(lang)}
${_seriesLine(seriesCtx)}

${buildItems(dawnStepItems['core_message']!, selectedKeys)}
''',
  'meditation': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n이 본문을 바탕으로 묵상을 돕는 글을 작성하세요.
문체: "~이다", "~한다" 서술체만 사용. "사랑하는 여러분", "~해 봅시다" 등 구어체·청중 호칭 절대 금지.
구조: 아래 각 항목을 번호(1. 2. 3.)로 시작하고, 항목 사이에 반드시 빈 줄을 한 줄 넣어 구분하세요.
분량: 약 900~1,200자.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}
언어: ${_langName(lang)}

${buildItems(dawnStepItems['meditation']!, selectedKeys)}
''',
  'application': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n이 본문의 삶의 적용을 해설하는 글을 작성하세요.
문체: "~이다", "~한다" 서술체만 사용. "사랑하는 여러분", "~해 봅시다" 등 구어체·청중 호칭 절대 금지.
구조: 아래 각 항목을 번호(1. 2. 3.)로 시작하고, 항목 사이에 반드시 빈 줄을 한 줄 넣어 구분하세요.
분량: 약 900~1,200자.

본문: $passage
번역본: ${_or(bible, '개역개정성경')}
언어: ${_langName(lang)}

${buildItems(dawnStepItems['application']!, selectedKeys)}
''',
  'prayer_topics': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n당신은 새벽 기도회를 섬기는 목회자입니다. 오늘 본문을 중심으로 성도들이 함께 기도할 내용을 작성해 주세요.
약 800~1,100자, 성도들이 바로 따라 기도할 수 있는 실제 기도문 형식으로 써 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}

${buildItems(dawnStepItems['prayer_topics']!, selectedKeys)}
- 각 기도는 4~6문장, 성도들이 마음으로 따라할 수 있는 언어로
''',
  'hymn': (passage, lang, bible, seriesCtx, selectedKeys) => '''\n당신은 교회 음악을 잘 아는 목회자입니다. 오늘 새벽 기도 본문에 가장 잘 어울리는 찬송을 추천해 주세요.
간결하고 실용적으로, 목회자가 바로 선곡에 참고할 수 있게 써 주세요.

본문: $passage
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}
찬송가 기준: 대한찬송가공회 2006년 발행 찬송가 (총 645장)

[대한찬송가공회 찬송가 전체 목록 - 반드시 이 목록의 번호와 제목을 그대로 사용하세요]
${getHymnListText()}

${buildItems(dawnStepItems['hymn']!, selectedKeys)}
''',
};

// ── 예배 통합 생성 ───────────────────────────────────────────

/// JS `Object.values(customStepTexts).filter(Boolean).join('\n')`
String _joinCustom(Map<String, String> customStepTexts) =>
    customStepTexts.values.where((t) => t.isNotEmpty).join('\n');

/// 단계별로 선택된 지시항목(없으면 전부)으로 항목 글을 만든다 — 웹 sel()
String _sel(Map<String, List<StepItem>> all, Map<String, List<String>>? stepSelectedItems, String key) {
  final items = all[key] ?? const <StepItem>[];
  if (items.isEmpty) return '';
  final selected = stepSelectedItems?[key];
  return buildItems(items, selected ?? items.map((i) => i.key).toList());
}

BuiltPrompt buildWorshipCombinedPrompt(String? date, String? season, String? lectionary, String lang, String? bible,
    Map<String, List<String>>? stepSelectedItems,
    [String userKeyword = '', Map<String, String> customStepTexts = const {}, String memory = '']) {
  String sel(String key) => _sel(worshipStepItems, stepSelectedItems, key);

  var prompt = '''예배 인도자를 위한 완성된 주일 예배 가이드를 A4 3~4장 분량(약 4,000~5,500자)으로 작성해 주세요.
각 순서별로 예배에서 바로 사용할 수 있게 실용적으로 작성해 주세요.
기도문과 축도문은 진행 지시어나 괄호 안 설명 없이 바로 낭독할 수 있는 본문만 작성하세요.

${_worshipHeader(date, season, lectionary, lang, bible)}

[대한찬송가공회 찬송가 전체 목록]
찬송 추천([3], [7], [10] 항목)은 반드시 아래 목록의 번호와 제목을 그대로 사용하세요. 이 목록에 없는 번호나 제목은 절대 사용하지 마세요.
${getHymnListText()}

다음 예배 순서를 모두 포함하세요:

[1. 예배의 부름 성경구절]
${sel('call_verse')}
[참고 구절 DB — 아래 목록에서 절기와 성서정과에 가장 어울리는 구절을 우선 선택하세요]
${getRandomVerseText(callToWorshipVerses)}
구절 선택 원칙:
- 위 DB 목록을 우선 참고하되, 더 적합한 구절이 있으면 사용할 수 있습니다.
- 시편 100편, 시편 95:1-6, 시편 150편, 요한복음 4:24처럼 지나치게 자주 반복되는 구절은 반드시 피하세요.
- 신선하고 덜 알려진 구절을 찾아 주세요. 선택한 구절이 이 날짜·절기에 어울리는 이유를 한 줄로 설명하세요.

[2. 예배의 부름 기도문]
- 절기 분위기를 담아 회중을 예배로 부르는 기도문 (8~12줄)
- 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺을 것

[3. 예배를 여는 찬양]
- 예배를 시작하며 회중의 마음을 하나님께 향하게 하는 찬양 추천
${sel('opening_hymns')}

[4. 참회의 기도문]
- 해당 절기에 맞는 참회의 기도문 (8~12줄)
- 말과 생각과 행동, 마땅히 해야 할 일을 하지 않은 태만까지 구체적인 죄의 영역을 짚되, 누구나 공감할 수 있는 일반적인 언어로 작성
- 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺을 것

[5. 용서의 선언]
- 하나님의 용서와 사죄를 선언하는 성경구절 2~3개를 반드시 제시하세요.
- 각 구절은 참조(예: 요한일서 1:9)와 구절 전문(${_or(bible, '개역개정성경')} 번역 직접 인용)을 함께 적으세요. 구절 내용을 생략하지 마세요.
[참고 구절 DB — 아래 목록에서 절기에 가장 어울리는 구절을 우선 선택하세요]
${getRandomVerseText(forgivenessVerses)}
- 위 DB 목록을 우선 참고하되, 요한일서 1:9·시편 103:12처럼 매주 반복되는 구절은 피하고, 구약과 신약을 골고루 선택하세요.
${sel('forgiveness')}

[6. 교독문]
반드시 찬송가공회(한국찬송가공회) 찬송가 뒤에 수록된 교독문만을 참고하세요.
${sel('responsive_reading')}

[7. 설교전찬양]
- 설교를 앞두고 회중이 말씀을 받을 준비를 하도록 돕는 찬양 추천
${sel('pre_sermon_hymns')}

[8. 예배를 위한 기도문]
- 찬양 → 감사 → 회개 → 중보(국가/사회/교회/예배) → 간구(가정/성도의 필요) 순서로 구성 (45~60줄)
- 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺을 것

[9. 봉헌기도문]
- 헌금의 감사와 절기 정신을 담은 봉헌기도문 (8~12줄)
- 마지막은 반드시 "예수님의 이름으로 기도합니다. 아멘."으로 끝맺을 것

[10. 설교후찬양]
- 설교 후 회중이 말씀에 응답하고 결단하도록 돕는 찬양 추천
${sel('post_sermon_hymns')}

[11. 파송의 말씀]
${sel('sending')}

[12. 축도]
- "주 예수 그리스도의 은혜와, ~~~하나님의 사랑과, ~~~성령의 위로(교통)하심이 ~~~ 성도 위에 함께 하시기를 축원하노라" 형식으로 작성. 삼위 각각의 수식어를 절기와 말씀에 맞게 채울 것. (8~12줄)
''';
  final extraCustom = _joinCustom(customStepTexts);
  if (extraCustom.isNotEmpty) prompt += '\n\n[추가 지시항목]\n$extraCustom';
  prompt = withCitationPolicy(prompt, lang);
  if (memory.isNotEmpty) prompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) prompt += '\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  return (prompt: prompt, systemExtra: '');
}

Future<String> generateWorshipCombined(String? date, String? season, String? lectionary, String lang, String? bible,
    Map<String, List<String>>? stepSelectedItems, ChunkCallback? onChunk,
    [String userKeyword = '', Map<String, String> customStepTexts = const {}, String memory = '']) {
  final b = buildWorshipCombinedPrompt(
      date, season, lectionary, lang, bible, stepSelectedItems, userKeyword, customStepTexts, memory);
  return streamCompletion(b.prompt, onChunk);
}

// ── 새벽 통합 생성 ───────────────────────────────────────────

const dawnStyleSystem =
    '절대로 "사랑하는 여러분", "함께", "~해 봅시다", "~하십시오", "~하세요" 같은 구어체·청중 호칭 표현을 사용하지 마세요. 모든 내용은 문어체(해설체)로, 독자가 혼자 읽으며 이해할 수 있는 산문으로 서술하세요.';

BuiltPrompt buildDawnCombinedPrompt(String? passage, String? emphasis, String lang, String? bible, String? seriesCtx,
    Map<String, List<String>>? stepSelectedItems,
    [String userKeyword = '', Map<String, String> customStepTexts = const {}, String memory = '']) {
  String sel(String key) => _sel(dawnStepItems, stepSelectedItems, key);

  var prompt = '''아래 본문을 바탕으로 새벽 기도회 전체 순서에 사용할 수 있는 말씀 자료를 A4 3~4장 분량(약 4,000~5,500자)으로 문어체로 작성해 주세요.
"사랑하는 여러분", "~해 봅시다", "~하십시오" 같은 구어체·청중 호칭은 절대 사용하지 말고, 설명하듯·해설하듯 서술하는 문어 산문으로 써 주세요.
전체 흐름 원칙: 본문 해설을 충분히 다룬 뒤, 그 해설에서 핵심 메시지를 자연스럽게 도출하고, 이어서 묵상 → 적용·결단 → 기도 순서가 하나의 유기적 흐름이 되도록 작성하세요. 각 단계는 앞 단계의 내용을 이어받아 전개되어야 합니다.
각 섹션 내 지시항목은 반드시 번호(1. 2. 3.)를 붙이고, 항목 사이에 빈 줄을 두어 명확히 구분하세요.

본문: ${passage ?? ''}
응답 언어: ${_langName(lang)}
기본 번역본: ${_or(bible, '개역개정성경')}
${_has(seriesCtx) ? '\n$seriesCtx\n이 시리즈의 흐름을 이어가는 내용을 써 주세요.' : ''}
${_has(emphasis) ? '\n강조하고 싶은 주제: $emphasis' : ''}

[대한찬송가공회 찬송가 전체 목록]
[6. 찬송 추천]은 반드시 아래 목록의 번호와 제목을 그대로 사용하세요. 이 목록에 없는 번호나 제목은 절대 사용하지 마세요.
${getHymnListText()}

다음 내용을 모두 포함하세요:

[1. 본문 해설]
${sel('exposition')}
- 문어체 해설 형식으로 작성

[2-4. 핵심 메시지 · 묵상 · 적용]
아래 구조를 두 번 반복하세요. 첫 번째 핵심 메시지를 전한 뒤, 바로 이어서 그에 따른 묵상 안내와 적용을 제시합니다. 그 다음 두 번째 핵심 메시지와 그에 따른 묵상·적용을 이어서 작성합니다.

[핵심 메시지 1]
${sel('core_message')}

[묵상 1]
${sel('meditation')}

[적용 1]
${sel('application')}

[핵심 메시지 2]
${sel('core_message')}

[묵상 2]
${sel('meditation')}

[적용 2]
${sel('application')}

[5. 기도 제목]
${sel('prayer_topics')}
- 각 기도는 4~6문장, 성도들이 마음으로 따라할 수 있는 언어로

[6. 찬송 추천]
${sel('hymn')}
''';
  final extraCustom = _joinCustom(customStepTexts);
  if (extraCustom.isNotEmpty) prompt += '\n\n[추가 지시항목]\n$extraCustom';
  prompt = withCitationPolicy(prompt, lang);
  if (memory.isNotEmpty) prompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) prompt += '\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  return (prompt: prompt, systemExtra: dawnStyleSystem);
}

Future<String> generateDawnCombined(String? passage, String? emphasis, String lang, String? bible, String? seriesCtx,
    Map<String, List<String>>? stepSelectedItems, ChunkCallback? onChunk,
    [String userKeyword = '', Map<String, String> customStepTexts = const {}, String memory = '']) {
  final b = buildDawnCombinedPrompt(
      passage, emphasis, lang, bible, seriesCtx, stepSelectedItems, userKeyword, customStepTexts, memory);
  return streamCompletion(b.prompt, onChunk, systemExtra: b.systemExtra);
}

// ── 예배 단계 생성 ───────────────────────────────────────────

BuiltPrompt buildWorshipStepPrompt(String stepKey, String? date, String? season, String? lectionary, String lang,
    String? bible,
    [List<String>? selectedItems, String userKeyword = '', String memory = '']) {
  final fn = _worshipStepPrompts[stepKey];
  if (fn == null) throw Exception('Unknown worship step key: $stepKey');
  var prompt = fn(date ?? '', season, lectionary, lang, bible, selectedItems);
  prompt = withCitationPolicy(prompt, lang);
  if (memory.isNotEmpty) prompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) prompt += '\n\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  return (prompt: prompt, systemExtra: '');
}

Future<String> generateWorshipStep(String stepKey, String? date, String? season, String? lectionary, String lang,
    String? bible, ChunkCallback? onChunk,
    [List<String>? selectedItems, String userKeyword = '', String memory = '']) {
  final b =
      buildWorshipStepPrompt(stepKey, date, season, lectionary, lang, bible, selectedItems, userKeyword, memory);
  return streamCompletion(b.prompt, onChunk);
}

// ── 새벽 단계 생성 ───────────────────────────────────────────

BuiltPrompt buildDawnStepPrompt(String stepKey, String? passage, String? emphasis, String lang, String? bible,
    String? seriesCtx,
    [List<String>? selectedItems, String userKeyword = '', String memory = '']) {
  final promptFn = _dawnStepPrompts[stepKey];
  if (promptFn == null) throw Exception('Unknown step key: $stepKey');
  final base = promptFn(passage ?? '', lang, bible, seriesCtx, selectedItems);
  var prompt = _has(emphasis) ? '$base\n\n강조하고 싶은 주제: $emphasis' : base;
  prompt = withCitationPolicy(prompt, lang);
  if (memory.isNotEmpty) prompt += '\n\n$memory';
  if (userKeyword.isNotEmpty) prompt += '\n\n[필수 반영 — 아래 키워드/지시를 결과에 반드시 명확하게 담으세요]: $userKeyword';
  final extra = const ['exposition', 'core_message', 'meditation', 'application'].contains(stepKey) ? dawnStyleSystem : '';
  return (prompt: prompt, systemExtra: extra);
}

Future<String> generateDawnStep(String stepKey, String? passage, String? emphasis, String lang, String? bible,
    String? seriesCtx, ChunkCallback? onChunk,
    [List<String>? selectedItems, String userKeyword = '', String memory = '']) {
  final b = buildDawnStepPrompt(stepKey, passage, emphasis, lang, bible, seriesCtx, selectedItems, userKeyword, memory);
  return streamCompletion(b.prompt, onChunk, systemExtra: b.systemExtra);
}

// ── 설교문 편집 ──────────────────────────────────────────────

String _bibleRef(String? bible, String lang) => _or(bible, lang == 'en' ? 'ESV' : '개역개정');

String _stepsText(List<StepData> stepsData) => stepsData.map((s) => '## ${s.label}\n${s.content}').join('\n\n');

BuiltPrompt buildInlineCommandPrompt(String instruction, String contextBefore, String contextAfter, String lang,
    String? bible, String? passage, String? title,
    [List<StepData>? stepsData, bool useTheological = false]) {
  final bibleRef = _bibleRef(bible, lang);
  final sermonInfo = [
    _has(passage) ? '설교 본문: $passage' : '',
    _has(title) ? '설교 제목: $title' : '',
  ].where((s) => s.isNotEmpty).join('\n');

  final stepsText = (stepsData != null && stepsData.isNotEmpty)
      ? '\n[단계별 연구 참고 — 아래 연구 내용을 지시사항 수행에 적극 활용하세요]\n${_stepsText(stepsData)}'
      : '';

  final theologicalText = useTheological
      ? '\n[신학적 외부 지식 활용]\n이 지시를 수행할 때, 칼빈·루터·바르트·팀 켈러·존 스토트·N.T. 라이트 등 신학자들의 관점, 주석 전통, 성경신학적 통찰, 교회사적 사례를 적극 활용하세요. 단계별 연구에 없는 새로운 신학적 자료와 시각을 제공하는 것이 이 지시의 목적입니다.'
      : '';

  final contextSection = (contextBefore.isNotEmpty || contextAfter.isNotEmpty)
      ? '\n[앞 문맥]\n${_lastChars(contextBefore, 600)}\n\n[뒤 문맥]\n${_firstChars(contextAfter, 600)}'
      : '';

  final prompt = '''당신은 설교 작성 전문가입니다.

아래 설교문의 지정된 위치에 들어갈 내용을 생성해 주세요.
모든 답변은 반드시 설교 본문 말씀을 중심으로 작성하세요.

$sermonInfo
$stepsText
$theologicalText

[지시사항]: $instruction
$contextSection

생성된 내용만 출력하세요. 별도 설명이나 머리말 없이.
[사용 성경]: $bibleRef''';

  return (prompt: prompt, systemExtra: '');
}

Future<String> executeInlineCommand(String instruction, String contextBefore, String contextAfter, String lang,
    String? bible, String? passage, String? title, ChunkCallback? onChunk,
    [List<StepData>? stepsData, bool useTheological = false]) {
  final b = buildInlineCommandPrompt(
      instruction, contextBefore, contextAfter, lang, bible, passage, title, stepsData, useTheological);
  return streamCompletion(b.prompt, onChunk);
}

/// 드래그로 선택한 부분만 지시대로 고친다 (내용·핵심 유지)
BuiltPrompt buildSelectionEditPrompt(String selectedText, String instruction, String contextBefore,
    String contextAfter, String lang, String? bible, String? passage, String? title) {
  final bibleRef = _bibleRef(bible, lang);
  final info = [
    _has(passage) ? '본문: $passage' : '',
    _has(title) ? '제목: $title' : '',
  ].where((s) => s.isNotEmpty).join('\n');

  final prompt = '''아래 [선택한 글]을 [지시사항]대로 고쳐 주세요.

[원칙]
- 원래 글의 내용과 핵심 메시지는 반드시 유지할 것
- 지시사항이 요구하는 부분만 고치고, 새로운 내용을 임의로 덧붙이지 말 것
- 문단 수와 문단 나눔은 지시사항이 요구하지 않는 한 그대로 유지할 것
- 앞뒤 문맥과 자연스럽게 이어지도록 할 것
- 고친 글만 출력할 것. 설명·머리말·따옴표 없이

$info
[사용 성경]: $bibleRef

[지시사항]: $instruction

[앞 문맥]
$contextBefore

[선택한 글]
$selectedText

[뒤 문맥]
$contextAfter''';

  const systemExtra = '이 요청은 이미 쓴 글의 일부를 고치는 작업입니다. 번호 붙이기 규칙은 적용하지 말고, 원래 글의 형식(번호 유무, 문단 구성)을 그대로 따르세요.';
  return (prompt: prompt, systemExtra: systemExtra);
}

Future<String> executeSelectionEdit(String selectedText, String instruction, String contextBefore,
    String contextAfter, String lang, String? bible, String? passage, String? title, ChunkCallback? onChunk) {
  final b = buildSelectionEditPrompt(selectedText, instruction, contextBefore, contextAfter, lang, bible, passage, title);
  return streamCompletion(b.prompt, onChunk, systemExtra: b.systemExtra);
}

BuiltPrompt buildDraftFromStepsPrompt(List<StepData> stepsData, String? passage, String? title, String? date,
    String lang, String? bible, String? userKeyword) {
  final bibleRef = _bibleRef(bible, lang);
  final stepsText = _stepsText(stepsData);
  final prompt = lang == 'en'
      ? '''You are a sermon writing expert. Based on the pastor's own research below, write a complete sermon draft.

Passage: ${passage ?? ''}
Title: ${_or(title, '(untitled)')}
Date: ${date ?? ''}
Bible version: $bibleRef
${_has(userKeyword) ? 'Directive: $userKeyword' : ''}

[Pastor's Research by Stage]
$stepsText

[Principles]
- Faithfully reflect the above research — do not fabricate content not present in the research.
- Structure as introduction → body → conclusion, connected naturally without section headers.
- Integrate the original language study, theological insights, illustrations, and applications into the sermon text.
- Write in preaching style, easy for the congregation to follow.
- Approximately 2–3 pages (A4) in length.'''
      : '''당신은 설교 작성 전문가입니다. 아래 목사님의 단계별 연구 내용을 바탕으로 설교문 초안을 작성해 주세요.

본문: ${passage ?? ''}
제목: ${_or(title, '(미정)')}
날짜: ${date ?? ''}
사용 성경: $bibleRef
${_has(userKeyword) ? '추가 지시: $userKeyword' : ''}

[단계별 연구 내용]
$stepsText

[작성 원칙]
- 위 연구 내용을 충실히 반영하되, 없는 내용을 임의로 만들어 넣지 말 것.
- 서론-본론-결론 구조로 자연스럽게 연결하되, 단락 제목 없이 흐름으로 이어갈 것.
- 원어 해설, 신학적 의미, 예화, 적용이 설교문 안에 자연스럽게 녹아들게 할 것.
- 강단에서 낭독하기 적합한 설교체로 작성할 것.
- 분량은 A4 2~3장 수준으로 작성할 것.''';
  return (prompt: prompt, systemExtra: '');
}

Future<String> generateDraftFromSteps(List<StepData> stepsData, String? passage, String? title, String? date,
    String lang, String? bible, String? userKeyword, ChunkCallback? onChunk) {
  final b = buildDraftFromStepsPrompt(stepsData, passage, title, date, lang, bible, userKeyword);
  return streamCompletion(b.prompt, onChunk);
}

BuiltPrompt buildRefineDraftPrompt(String draft, String lang, String? bible) {
  final bibleRef = _bibleRef(bible, lang);
  final prompt = lang == 'en'
      ? '''You are a sermon writing expert.

Below is a sermon draft assembled from multiple research stages. Please refine it into a single, naturally flowing sermon.

[Principles]
- Preserve the original order and core content
- Connect paragraph transitions naturally
- Remove duplicate expressions (keep only once)
- Do not add or delete content arbitrarily
- Ensure it reads as a coherent, well-structured sermon
[Bible version]: $bibleRef

[Sermon draft]
$draft'''
      : '''당신은 설교 작성 전문가입니다.

아래는 여러 단계에서 작성된 설교 초안입니다. 이 내용을 자연스럽고 유기적으로 흐르는 하나의 설교문으로 다듬어 주세요.

[다듬기 원칙]
- 원래 내용의 순서와 핵심을 최대한 유지할 것
- 단락 간 전환을 자연스럽게 연결할 것
- 중복되는 표현은 한 번만 남길 것
- 임의로 내용을 추가하거나 삭제하지 말 것
- 설교문으로서의 언어 흐름을 갖출 것
[사용 성경]: $bibleRef

[설교 초안]
$draft''';
  return (prompt: prompt, systemExtra: '');
}

Future<String> refineDraft(String draft, String lang, String? bible, ChunkCallback? onChunk) {
  final b = buildRefineDraftPrompt(draft, lang, bible);
  return streamCompletion(b.prompt, onChunk);
}
