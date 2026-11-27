# 작업 지침 (Claude Usage — macOS 메뉴 바 앱)

## 구조
- Swift Package, 소스: `Sources/ClaudeUsageMonitor/` (SwiftUI `MenuBarExtra`)
- 빌드 확인: `swift build -c release` · 패키징: `bash packaging/build.sh` → [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- UI 문구는 한국어

## 릴리즈
1. `packaging/Info.plist`의 `CFBundleShortVersionString`을 올린다 (패치 단위가 기본).
2. 커밋 메시지 형식: `<변경 요약> (x.y.z)`.
3. `main`에 push → `git tag vX.Y.Z && git push origin vX.Y.Z` → GitHub Actions가 서명·공증·Release·Homebrew cask 갱신.
4. Release 워크플로 완료를 확인하고, Release 노트에 변경 내용을 적는다. 자세한 내용은 [docs/RELEASE.md](docs/RELEASE.md).

## 개발 버전 정리 (필수)
- 개발 중 개발 빌드를 이 Mac에 설치하거나 실행했다면(`/Applications`·`~/Applications` 복사, `open dist/*.app`,
  bare 바이너리 실행, 로그인 항목 등록 등) **작업 완료 후 반드시 종료하고 삭제한다.**
  정식 설치본(Homebrew cask `claude-usage`, `/Applications/Claude Usage.app`)과 번들 ID·UserDefaults·키체인·
  로그인 항목을 공유하므로 충돌한다.
- 정리 후 정식 설치본이 정상 실행 중인지 확인한다(필요하면 `brew upgrade --cask claude-usage` 또는
  `brew reinstall --cask claude-usage`, 그 뒤 `open -a "Claude Usage"`).
- `dist/`의 빌드 산출물은 git에 포함되지 않으며 지워도 된다.
