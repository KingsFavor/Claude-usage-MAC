# Development

로컬에서 빌드·패키징·공증하는 방법입니다. GitHub에서 태그 기반으로 자동 릴리즈하는 방법은
[RELEASE.md](RELEASE.md)를 참고하세요.

## 요구사항
- macOS 14+ · **Xcode 16+ / Swift 6**
- 공증까지 하려면: **Apple Developer 계정** + **Developer ID Application** 인증서

## 로컬 빌드 & 실행
```bash
swift build -c release                # 컴파일만
.build/release/ClaudeUsageMonitor     # 번들 없이 메뉴 바에서 바로 실행 (테스트용)
```

## 전체 패키징 (앱 번들 + 서명 + 공증 + DMG)
```bash
bash packaging/build.sh
```
순서대로 수행합니다: 컴파일 → `.app` 번들 조립(+아이콘) → **Developer ID 서명**(hardened runtime)
→ **앱 공증·staple** → **드래그 안내 화면 포함 DMG 생성** → **DMG 공증·staple** → Gatekeeper 검증.

산출물:
- `dist/Claude Usage.app`
- `dist/Claude-Usage-<버전>.dmg`

스크립트는 환경 변수로 조정할 수 있습니다:
- `VERSION` — 마케팅 버전 (기본값: `packaging/Info.plist`의 `CFBundleShortVersionString`)
- `SIGN_ID` — Developer ID Application 서명 이름
- `NOTARIZE=1|0` — 공증 강제 on/off (기본: 자격증명이 있으면 자동 on)

## 로컬 공증 자격증명 (1회 설정)
공증은 `claude-usage`라는 notarytool 키체인 프로파일이 있으면 **자동 실행**됩니다.

먼저 앱 전용 암호를 발급하세요: **appleid.apple.com → 로그인 및 보안 → 앱 전용 암호 → 생성**.

```bash
xcrun notarytool store-credentials claude-usage \
  --apple-id "<APPLE_ID 이메일>" --team-id 4S9VPFZ465
# → Password: 에 앱 전용 암호 붙여넣기
```
- `--team-id`는 본인 Developer 팀 ID로 바꾸세요(현재 값 `4S9VPFZ465` = Kwonwoo Lyu).
- 다른 인증서로 서명한다면 `packaging/build.sh`의 `SIGN_ID`도 본인 이름으로 수정하세요.
- 저장 확인: `xcrun notarytool history --keychain-profile claude-usage`

> App Store Connect API 키를 대신 쓰려면 `NOTARY_KEY`/`NOTARY_KEY_ID`/`NOTARY_ISSUER` 환경
> 변수를 지정하면 됩니다(CI가 쓰는 방식). 자세한 내용은 [RELEASE.md](RELEASE.md).

## 공증 검증
```bash
spctl --assess --type execute --verbose=2 "dist/Claude Usage.app"
# 기대 결과:  accepted / source=Notarized Developer ID
xcrun stapler validate "dist/Claude Usage.app"
xcrun stapler validate "dist/Claude-Usage-<버전>.dmg"
```

> 공증 없이 빌드하면(`NOTARIZE=0` 또는 프로파일 없음) Developer ID 서명만 됩니다. 본인 Mac에서
> 로컬 빌드로 실행할 땐 quarantine이 없어 경고가 없지만, **다운로드한 복사본**은 공증이 없으면 경고가 납니다.

## 버전 올리기
`packaging/Info.plist`의 `CFBundleShortVersionString`(및 `CFBundleVersion`)을 수정합니다.
- 로컬 빌드: `VERSION=1.2.3 bash packaging/build.sh` 또는 Info.plist 값 그대로 사용.
- 자동 릴리즈: 버전 태그를 push하면 CI가 처리합니다 → [RELEASE.md](RELEASE.md).

## 앱 아이콘 재생성
로고는 `packaging/logo_src.png`(형상이 알파 채널에 있는 PNG)에서 생성합니다.
```bash
python3 tools/make_icon_from_png.py                 # packaging/AppIcon.iconset 갱신
iconutil -c icns packaging/AppIcon.iconset -o packaging/AppIcon.icns
```
알파 채널의 픽셀아트를 흰색으로 보정해 검정 라운드-렉트(macOS 아이콘 그리드) 위에 중앙 배치합니다.
