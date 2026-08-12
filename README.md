<p align="center">
  <img src="assets/logo.png" width="140" alt="Claude Usage 로고">
</p>

<h1 align="center">Claude Usage</h1>

<p align="center">
  macOS 메뉴 바에서 <b>Claude 플랜 전체 사용량</b>(claude.ai 채팅 + Claude Code 통합)을 보여주는 앱
</p>

메뉴 바 아이콘을 누르면 `/usage` 패널과 동일한 정보 + 사용량 추이 그래프가 드롭다운으로 열립니다.

## 기능
- **현재 세션(5시간 윈도우)** · **주간 한도(모든 모델/Opus)** 사용률 % + 리셋까지 남은 시간
- 메뉴 바 아이콘에 현재 세션 % 실시간 표시
- **사용량 추이 그래프** — 분/시간/일 단위 토글, `사용률`(누적 %) / `소진속도`(구간별 증가량) 토글
- 폴링 주기(1/5/15/30분) 설정, 수동 새로고침 (기본 5분 — 과도한 요청으로 인한 rate limit 방지)
- 토큰 만료 시 자동 갱신

## 설치

### Homebrew (권장)
```bash
brew install --cask kingsfavor/tap/claude-usage
```
> 최신 Homebrew에서 서드파티 tap 최초 사용 시 신뢰 확인을 요구하면 `brew trust kingsfavor/tap`을 한 번 실행하세요.

업데이트는 `brew upgrade --cask claude-usage`.

### DMG 직접 내려받기
1. [Releases](https://github.com/KingsFavor/Claude-usage-MAC/releases/latest)에서 최신 `Claude-Usage-*.dmg`를 받아 더블클릭합니다.
2. 안내(화살표)대로 **`Claude Usage` 아이콘을 `Applications` 폴더로 드래그**합니다.
3. Launchpad 또는 응용 프로그램 폴더에서 실행합니다. 앱은 Apple **공증(notarization)** 을 받았으므로 경고 없이 바로 실행됩니다.

## 업데이트
새 버전이 나오면 앱이 **드롭다운 안에 은은한 배너**("새 버전 x.y.z 사용 가능")로 알려줍니다.
방해되는 팝업·시스템 알림은 없으며, 배너의 **×** 로 그 버전 알림을 끌 수 있습니다.
(GitHub 릴리즈를 최대 6시간에 한 번만 조용히 확인합니다.)

직접 확인하고 싶으면 드롭다운 왼쪽 아래의 **"vX.Y.Z · 업데이트 확인"** 을 누르세요 —
새 버전이 있으면 위 배너가, 없으면 잠깐 "최신 버전이에요" 표시가 뜹니다.

실제 업데이트 방법:
- **Homebrew**: `brew upgrade --cask claude-usage`
- **DMG**: 배너의 **업데이트** 버튼(또는 [Releases](https://github.com/KingsFavor/Claude-usage-MAC/releases/latest))에서 최신 DMG를 받아 다시 드래그 설치

## 사용 & 로그인
메뉴 바에 아이콘이 생기면 클릭 → **"Claude로 로그인"** → 브라우저에서 Claude 계정을 승인하면 사용량이 표시됩니다.

인증은 두 가지 방식을 지원합니다(우선순위 순):
1. **앱 내 로그인** — 드롭다운의 **"Claude로 로그인"** 버튼으로 브라우저에서 Claude 계정을 승인(OAuth PKCE)합니다. 토큰은 앱 전용 키체인 항목(`ClaudeUsageMonitor-credentials`)에 저장되며, **Claude Code 없이도 단독으로 동작합니다.**
2. **Claude Code 토큰 폴백** — 앱 로그인이 없으면 이미 로그인된 Claude Code의 토큰을 재사용합니다.

푸터의 로그아웃 버튼으로 앱 토큰을 삭제할 수 있습니다.

> **메뉴 바에서 항상 실행되게 하려면**: 시스템 설정 → 일반 → 로그인 항목 → `+`로 `Claude Usage` 추가.
>
> **키체인 프롬프트 안내**: *Claude Code의 로그인을 재사용*하는 경우에만 최초 1회 *"Claude Usage가 키체인의 기밀 정보를 사용하려고 합니다"* 프롬프트가 뜹니다. **항상 허용**을 누르세요. (macOS 보안 절차이며 Gatekeeper 경고와 무관)

## 데이터 & 개인정보
- 한도/사용률은 Claude Code가 쓰는 것과 동일한 엔드포인트(`GET https://api.anthropic.com/api/oauth/usage`, 플랜 단위 통합 한도)에서 가져옵니다.
- 추이 그래프용 시계열은 **로컬에만** 저장됩니다: `~/Library/Application Support/ClaudeUsageMonitor/snapshots.json` (최근 30일 보관). 외부로 전송하지 않습니다.

## 제거

### Homebrew로 설치한 경우
```bash
brew uninstall --cask claude-usage         # 앱만 삭제
brew uninstall --zap --cask claude-usage   # 앱 + 설정·추이 그래프 데이터까지 완전 삭제
```
`--zap`은 설정(preferences)과 추이 그래프 스냅샷(`~/Library/Application Support/ClaudeUsageMonitor`)까지 함께 지웁니다.

### 수동(DMG)으로 설치한 경우
`Applications`에서 `Claude Usage.app`을 휴지통으로 이동.

### 로그인 토큰까지 정리 (선택)
로그인 토큰은 키체인에 있어 `--zap`으로도 지워지지 않습니다. 완전히 지우려면:
```bash
security delete-generic-password -s "ClaudeUsageMonitor-credentials"  # 앱 로그인 토큰
```
> `--zap` 없이 지웠거나 수동 설치했다면, 남은 데이터도 함께 정리하세요:
> ```bash
> rm -rf ~/Library/Application\ Support/ClaudeUsageMonitor      # 추이 그래프 스냅샷
> defaults delete com.kwonwoo.claude-usage-monitor 2>/dev/null  # 앱 설정
> ```

## 개발자 · 기여
빌드·패키징·릴리즈 문서는 `docs/`에 있습니다:
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — 로컬 빌드, 패키징, 로컬 공증, 아이콘 재생성
- [docs/RELEASE.md](docs/RELEASE.md) — 태그 기반 자동 릴리즈(CI), 서명·공증, Homebrew cask 배포
