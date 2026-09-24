// 웹(bibleblok/src/constants.js)과 같은 내용

class StepDef {
  final int index;
  final String key;
  final String ko;
  final String en;
  const StepDef(this.index, this.key, this.ko, this.en);

  String label(String lang) => lang == 'en' ? en : ko;
}

const sermonSteps = [
  StepDef(0, 'narrative', '서사적 해설', 'Narrative Commentary'),
  StepDef(1, 'text_study', '본문연구', 'Textual Study'),
  StepDef(2, 'original', '원어 해설', 'Original Language'),
  StepDef(3, 'research', '확장 연구', 'Extended Research'),
  StepDef(4, 'message', '본문 메시지', 'Message'),
  StepDef(5, 'lesson', '교훈', 'Lessons'),
  StepDef(6, 'deep_questions', '심층질문', 'Deep Questions'),
  StepDef(7, 'application', '적용', 'Application'),
  StepDef(8, 'illustration', '예화', 'Illustrations'),
  StepDef(9, 'hymns', '찬송 선별', 'Hymns & CCM'),
];

const worshipSteps = [
  StepDef(0, 'call_verse', '예배의 부름 - 성경구절', 'Call to Worship (Scripture)'),
  StepDef(1, 'call_prayer', '예배의 부름 - 기도문', 'Call to Worship (Prayer)'),
  StepDef(2, 'opening_hymns', '예배를 여는 찬양', 'Opening Hymns'),
  StepDef(3, 'confession', '참회의 기도문', 'Prayer of Confession'),
  StepDef(4, 'forgiveness', '용서의 선언 - 성경구절', 'Assurance of Pardon'),
  StepDef(5, 'responsive_reading', '교독문', 'Responsive Reading'),
  StepDef(6, 'pre_sermon_hymns', '설교전찬양', 'Pre-Sermon Hymns'),
  StepDef(7, 'worship_prayer', '예배를 위한 기도문', 'Prayer for Worship'),
  StepDef(8, 'offering', '봉헌기도문', 'Offertory Prayer'),
  StepDef(9, 'post_sermon_hymns', '설교후찬양', 'Post-Sermon Hymns'),
  StepDef(10, 'sending', '파송의 말씀', 'Sending Word'),
  StepDef(11, 'benediction', '축도', 'Benediction'),
];

const dawnSteps = [
  StepDef(0, 'exposition', '본문 해설', 'Exposition'),
  StepDef(1, 'core_message', '핵심 메시지', 'Core Message'),
  StepDef(2, 'meditation', '묵상', 'Meditation'),
  StepDef(3, 'application', '적용과 결단', 'Application'),
  StepDef(4, 'prayer_topics', '기도 제목', 'Prayer Topics'),
  StepDef(5, 'hymn', '찬송 선별', 'Hymn'),
];

const cellSteps = [
  StepDef(0, 'sharing', '나눔 교재', 'Sharing Material'),
  StepDef(1, 'gospel', '복음적 교재', 'Gospel Material'),
  StepDef(2, 'theological', '신학적 교재', 'Theological Material'),
  StepDef(3, 'literary', '문학적 교재', 'Literary Material'),
  StepDef(4, 'psychological', '심리학적 교재', 'Psychological Material'),
  StepDef(5, 'communal', '공동체적 교재', 'Communal Material'),
];

List<StepDef> stepsForTab(String tab) => switch (tab) {
      'sermon' => sermonSteps,
      'worship' => worshipSteps,
      'dawn' => dawnSteps,
      _ => cellSteps,
    };

class Option {
  final String code;
  final String ko;
  final String en;
  const Option(this.code, this.ko, [String? en]) : en = en ?? ko;
  String label(String lang) => lang == 'en' ? en : ko;
}

const languages = [Option('ko', '한국어'), Option('en', 'English')];

const bibleVersionsKo = [
  Option('개역개정성경', '개역개정'),
  Option('공동번역성경', '공동번역'),
  Option('새한글성경', '새한글성경'),
];

const bibleVersionsEn = [
  Option('ESV', 'ESV'),
  Option('NIV', 'NIV'),
  Option('NKJV', 'NKJV'),
  Option('NASB', 'NASB'),
  Option('NLT', 'NLT'),
  Option('KJV', 'KJV'),
];

const themes = [
  Option('system', '시스템', 'System'),
  Option('light', '라이트', 'Light'),
  Option('dark', '다크', 'Dark'),
];

const tabs = ['sermon', 'worship', 'dawn', 'cell'];

String tabLabel(String tab, String lang) => lang == 'en'
    ? const {'sermon': 'Sermon', 'worship': 'Worship', 'dawn': 'Dawn Prayer', 'cell': 'Cell Material'}[tab]!
    : const {'sermon': '설교작성', 'worship': '예배인도', 'dawn': '새벽설교', 'cell': '교재작성'}[tab]!;

// 저장 폴더 안에서 탭별 폴더 이름
const tabDirNames = {'sermon': '설교작성', 'worship': '예배인도', 'dawn': '새벽설교', 'cell': '교재작성'};

String appName(String lang) => lang == 'en' ? 'Bible & Sermon' : '성경과설교';
