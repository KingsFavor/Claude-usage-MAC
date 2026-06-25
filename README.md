# Claude Usage

macOS 메뉴 바에서 **Claude 플랜 전체 사용량**(claude.ai 채팅 + Claude Code 통합)을 보여주는 앱입니다.
메뉴 바 아이콘을 누르면 `/usage` 패널과 동일한 정보 + 사용량 추이(burst) 그래프가 드롭다운으로 열립니다.

## 기능
- **현재 세션(5시간 윈도우)** · **주간 한도(모든 모델/Opus)** 사용률 % + 리셋까지 남은 시간
- 메뉴 바 아이콘에 현재 세션 % 실시간 표시
- **사용량 추이 그래프** — 분/시간/일 단위 토글, `사용률`(누적 %) / `소진속도`(구간별 증가량) 토글
- 폴링 주기(30/60/120/300초) 설정, 수동 새로고침
- 토큰 만료 시 자동 갱신

## 로그인
앱은 두 가지 방식으로 인증합니다(우선순위 순):
1. **앱 내 로그인** — 드롭다운의 **"Claude로 로그인"** 버튼 → 브라우저에서 Claude 계정 승인(OAuth PKCE) → 토큰을 앱 전용 키체인 항목(`ClaudeUsageMonitor-credentials`)에 저장. **Claude Code 없이도 단독으로 동작합니다.**
2. **Claude Code 토큰 폴백** — 앱 로그인이 없으면, 이미 로그인된 Claude Code의 `Claude Code-credentials` 토큰을 재사용.

로그인 플로우: `claude.ai/oauth/authorize` → 로컬 루프백(`http://localhost:3118/callback`)으로 코드 수신 → `console.anthropic.com/v1/oauth/token` 교환. 만료 시 refresh 토큰으로 자동 갱신. 푸터의 로그아웃 버튼으로 앱 토큰을 삭제할 수 있습니다.

## 데이터 출처
- 한도/사용률: `GET https://api.anthropic.com/api/oauth/usage` (Claude Code가 쓰는 것과 동일한 비공식 엔드포인트, 플랜 단위 통합 한도)
- 추이 그래프: 위 엔드포인트는 현재 스냅샷만 주므로, 앱이 주기적으로 폴링해 `~/Library/Application Support/ClaudeUsageMonitor/snapshots.json`에 시계열을 적재(최근 30일 보관)

---

## 설치 방법 (사용자)

1. **`Claude-Usage-1.0.0.dmg`를 더블클릭**합니다.
2. 열린 창의 안내(화살표)대로 **`Claude Usage` 아이콘을 `Applications` 폴더로 드래그**합니다.
3. **Launchpad 또는 응용 프로그램 폴더에서 `Claude Usage`를 실행**합니다.
   - 앱은 Apple **공증(notarization)** 을 받았으므로 *"신뢰할 수 없는 앱"* 경고 없이 바로 실행됩니다.
4. 메뉴 바에 **검정 배경의 Claude 로고 아이콘**이 생깁니다. 클릭 → **"Claude로 로그인"** → 브라우저에서 Claude 계정을 승인하면 사용량이 표시됩니다.

> **메뉴 바에서 항상 실행되게 하려면**: 시스템 설정 → 일반 → 로그인 항목 → `+`로 `Claude Usage` 추가.
>
> **참고(키체인 프롬프트)**: 앱 내 로그인 대신 *이미 설치된 Claude Code의 로그인을 재사용*하는 경우에만, 최초 1회 *"Claude Usage가 키체인의 기밀 정보를 사용하려고 합니다"* 프롬프트가 뜹니다. **항상 허용**을 누르세요. (이는 macOS 보안 절차이며 Gatekeeper 경고와 무관)

### 제거
`Applications`에서 `Claude Usage.app`을 휴지통으로 이동. 저장 데이터까지 지우려면:
```bash
rm -rf ~/Library/Application\ Support/ClaudeUsageMonitor          # 추이 그래프 스냅샷
security delete-generic-password -s "ClaudeUsageMonitor-credentials"  # 앱 로그인 토큰
```

---

## 개발

### 요구사항
- macOS 14+ · **Xcode 16+ / Swift 6** (`xcode-select --install` 또는 Xcode 설치)
- 배포(공증)까지 하려면: **Apple Developer 계정** + **Developer ID Application** 인증서

### 로컬 빌드 & 실행
```bash
swift build -c release          # 컴파일만
.build/release/ClaudeUsageMonitor   # 메뉴 바에 떠서 바로 실행 (번들 없이 테스트용)
```

### 전체 패키징 (앱 번들 + 서명 + 공증 + DMG)
```bash
bash packaging/build.sh
```
이 한 줄이 순서대로 수행합니다: 컴파일 → `.app` 번들 조립(+아이콘) → **Developer ID 서명**(hardened runtime) → **앱 공증·staple** → **드래그 안내 화면 포함 DMG 생성** → **DMG 공증·staple** → Gatekeeper 검증.

산출물:
- `dist/Claude Usage.app`
- `dist/Claude-Usage-1.0.0.dmg`

공증 단계는 `claude-usage` 키체인 프로파일이 있을 때 **자동 실행**됩니다. 강제 토글: `NOTARIZE=1`(켜기) / `NOTARIZE=0`(끄기, 로컬 전용).

---

## 개발 후 공증 받기

다운로드/전송한 복사본까지 **어떤 Mac에서도 경고 없이** 실행되게 하려면 Apple 공증이 필요합니다.

### 1단계 — 자격증명 1회 저장 (최초 한 번만)
앱 전용 암호를 먼저 발급하세요: **appleid.apple.com → 로그인 및 보안 → 앱 전용 암호 → 생성** (`abcd-efgh-ijkl-mnop`).

그다음 터미널에서(비밀번호는 프롬프트로 입력받아 키체인에만 저장됩니다):
```bash
xcrun notarytool store-credentials claude-usage \
  --apple-id "<APPLE_ID 이메일>" --team-id 4S9VPFZ465
# → Password: 에 앱 전용 암호 붙여넣기
```
- `--team-id`는 본인 Developer 팀 ID로 바꾸세요(현재 값은 `4S9VPFZ465` = Kwonwoo Lyu).
- 다른 인증서로 서명한다면 `packaging/build.sh`의 `SIGN_ID`도 본인 *Developer ID Application* 이름으로 수정하세요.
- 저장 확인: `xcrun notarytool history --keychain-profile claude-usage`

### 2단계 — 빌드(공증 자동 포함)
```bash
bash packaging/build.sh
```
프로파일을 감지해 앱·DMG를 Apple 공증 서버에 제출하고(수 분 소요) 티켓을 staple까지 합니다.

### 3단계 — 검증
```bash
spctl --assess --type execute --verbose=2 "dist/Claude Usage.app"
# 기대 결과:  accepted / source=Notarized Developer ID
xcrun stapler validate "dist/Claude Usage.app"
xcrun stapler validate "dist/Claude-Usage-1.0.0.dmg"
```
`accepted · Notarized Developer ID`가 나오면 배포 준비 완료입니다.

> 공증 없이 빌드하면(`NOTARIZE=0` 또는 프로파일 없음) Developer ID 서명만 됩니다. **본인 Mac에서 로컬 빌드**로 실행할 땐 quarantine이 없어 경고가 없지만, **다운로드한 복사본**은 공증이 없으면 경고가 납니다.

### 버전 올리기
`packaging/build.sh`의 `VERSION`과 `packaging/Info.plist`의 `CFBundleShortVersionString`·`CFBundleVersion`을 함께 수정한 뒤 다시 빌드하세요.
