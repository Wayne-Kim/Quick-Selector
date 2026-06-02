# quick-desktop 구현 계획서

## 1. 목표

맥 상태바(menu bar)에 상주하면서 `~/Desktop` 폴더의 파일을 썸네일 그리드로 빠르게 열람하고,
거기서 바로 **드래그 앤 드롭으로 브라우저(특히 GitHub PR 첨부 영역)에 파일을 업로드**할 수 있는 네이티브 macOS 앱.

핵심 시나리오:
> 화면을 캡처/녹화 → 파일이 `~/Desktop`에 저장 → 다른 창에 가려져 있어도 상태바 아이콘 클릭 한 번으로 최신 파일이 맨 위에 보이고 → 거기서 GitHub PR 작성창으로 드래그.

---

## 2. 요구사항 정리

### 2.1 기능 요구사항 (확정)
| # | 항목 | 결정 |
|---|------|------|
| F1 | 상주 위치 | macOS 상태바 (NSStatusItem) |
| F2 | 대상 폴더 | `~/Desktop` 고정 |
| F3 | 표시 방식 | 썸네일 + 파일명 그리드 |
| F4 | 정렬 | 최근 수정순 (mtime DESC) |
| F5 | 핵심 인터랙션 | 그리드 셀에서 외부 앱으로 파일 드래그 |
| F6 | 실시간 반영 | Desktop에 새 파일이 생기면 자동 갱신 |

### 2.2 부가 기능 (이번 마일스톤 포함)
- 셀 우클릭 컨텍스트 메뉴: **Finder에서 보기 / 열기 / Quick Look / 휴지통**
- 더블클릭: 기본 앱으로 열기
- Space 키: Quick Look (선택 셀)
- 상태바 아이콘 클릭 시 팝업 토글, 빈 영역 클릭/ESC 시 닫힘

### 2.3 비기능 요구사항
- 메모리 점유 작게 (백그라운드 상주 앱이므로): 썸네일은 LRU 캐시.
- 드래그 도중 패널이 닫히지 않을 것 (NSPopover의 알려진 함정).
- macOS 권한(폴더 접근) 동의 흐름 자연스럽게.
- 다크/라이트 모드 모두 보기 좋게.

### 2.4 비범위 (이번엔 안 함)
- 다른 폴더 지원 / 설정 화면 (Desktop 고정으로 결정)
- App Store 배포(샌드박싱) — 개인 도구로 시작, 필요시 추후
- iCloud Drive 동기화 상태 표시
- 파일 검색창

---

## 3. 기술 스택 & 핵심 의사결정

| 영역 | 선택 | 이유 |
|------|------|------|
| 언어/UI | Swift + SwiftUI | 네이티브 드래그 promise 처리가 가장 매끄러움 |
| 최소 지원 OS | macOS 13 Ventura | `QLThumbnailGenerator` 안정 / SwiftUI 그리드 성숙 |
| 패키징 | Xcode 단일 앱 타깃 | LSUIElement=YES (Dock 아이콘 없음) |
| 샌드박싱 | **OFF** (1차) | 개인 사용. 추후 필요시 security-scoped bookmark 도입 |
| 파일 감시 | `DispatchSource.makeFileSystemObjectSource` + `kqueue` | 단일 디렉터리에 가벼움. FSEvents는 과함 |
| 썸네일 | `QuickLookThumbnailing.QLThumbnailGenerator` | 이미지·동영상·PDF 등 폭넓게 지원 |
| 드래그 캐리어 | `NSItemProvider(contentsOf: fileURL)` (UTI: `public.file-url`) | 파일이 디스크에 이미 있으므로 promise 불필요. 브라우저(Chrome/Safari)·Finder·메일 모두 이 형식 수용 |

### 3.1 가장 까다로운 부분: "드래그하면 팝업이 닫힘" 문제
NSPopover로 만들면 드래그 시작 시 마우스가 팝오버 밖으로 나가면서 자동 닫힘 → 드래그 세션이 끊기는 문제 발생.
**대응:** `NSPopover` 대신 **비활성 `NSPanel`** 사용.
- `styleMask = [.borderless, .nonactivatingPanel]`
- `level = .statusBar` 또는 `.popUpMenu`
- 상태바 버튼 클릭 시 패널을 버튼 아래에 위치시켜 표시 / 토글
- 외부 클릭 감지(`NSEvent.addGlobalMonitorForEvents`)로 닫기

---

## 4. 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│  AppDelegate                                                │
│   ├── NSStatusItem (상태바 아이콘)                          │
│   ├── NSPanel  ── hosts ──► SwiftUI ContentView             │
│   └── 글로벌 클릭 모니터 (외부 클릭 시 패널 닫기)            │
└─────────────────────────────────────────────────────────────┘
            │ owns
            ▼
┌─────────────────────────────────────────────────────────────┐
│  DesktopStore  (ObservableObject)                           │
│   ├── @Published files: [DesktopFile]                       │
│   ├── DesktopFolderObserver (kqueue watcher)                │
│   └── refresh() — FileManager.contentsOfDirectory + sort     │
└─────────────────────────────────────────────────────────────┘
            │ uses
            ▼
┌─────────────────────────────────────────────────────────────┐
│  ThumbnailCache                                             │
│   ├── NSCache<NSURL, NSImage>                               │
│   └── QLThumbnailGenerator (async 요청)                     │
└─────────────────────────────────────────────────────────────┘

SwiftUI 트리:
  ContentView (LazyVGrid)
    └── FileGridItem (썸네일 + 이름 + .onDrag + .contextMenu)
```

### 4.1 데이터 모델
```swift
struct DesktopFile: Identifiable, Hashable {
    let id: URL              // 파일 URL
    let name: String
    let modifiedAt: Date
    let size: Int64
    let isDirectory: Bool
}
```

### 4.2 갱신 전략
- 앱 시작 시 1회 `refresh()`
- `DesktopFolderObserver`가 write/extend/rename/delete 이벤트 수신 → debounce(200ms) → `refresh()`
- 패널이 표시될 때마다 `refresh()` 한 번 더 (안전망)

### 4.3 드래그 구현
```swift
.onDrag {
    NSItemProvider(contentsOf: file.id) ?? NSItemProvider()
}
```
- 드래그 시 셀의 썸네일 이미지를 preview로 사용 (`.onDrag { ... } preview: { thumbnailView }`)
- 추가: 드래그 시작 시 패널 닫지 않도록 NSPanel에서 처리 (위 3.1)

---

## 5. 프로젝트 구조

```
quick-desktop/
├── PLAN.md                          (본 문서)
├── quick-desktop.xcodeproj/
└── quick-desktop/
    ├── quick_desktopApp.swift       # @main, AppDelegate 위임
    ├── AppDelegate.swift            # 상태바·패널 lifecycle
    ├── StatusBarController.swift    # NSStatusItem 래퍼
    ├── PanelController.swift        # NSPanel 토글·위치 계산
    ├── DesktopStore.swift           # ObservableObject
    ├── DesktopFolderObserver.swift  # kqueue 기반 감시
    ├── ThumbnailCache.swift         # QLThumbnailGenerator + NSCache
    ├── Model/
    │   └── DesktopFile.swift
    ├── Views/
    │   ├── ContentView.swift        # LazyVGrid
    │   └── FileGridItem.swift       # 셀 + onDrag + contextMenu
    ├── Info.plist                   # LSUIElement=YES, NSDesktopFolderUsageDescription
    └── Assets.xcassets/             # 상태바 아이콘 (Template image)
```

---

## 6. UX 명세

### 6.1 상태바 아이콘
- SF Symbol: `folder.badge.gearshape` 또는 `square.stack.3d.up`
- Template 이미지로 설정 → 메뉴바 다크/라이트 자동 대응
- 클릭 시 패널 토글, 우클릭 시 메뉴 (Quit, About)

### 6.2 패널 레이아웃
- 너비: 360pt 고정
- 높이: 그리드 내용에 따라 가변, 최대 480pt (이후 스크롤)
- 그리드: 3열, 셀 한 변 100pt (썸네일 ~88pt + 파일명 2줄 truncate)
- 상단 헤더: "Desktop" 라벨 + 새로고침 버튼 + 파일 개수
- 빈 상태: "Desktop is empty" 일러스트 + 안내

### 6.3 셀
- 썸네일 (88×88, cornerRadius 8, border 0.5pt secondary)
- 파일명 (caption, 2줄 truncate)
- hover 시 배경 강조 + 그림자
- 드래그 시작 시 NSDraggingItem.imageComponentsProvider로 썸네일 그대로 carry
- contextMenu: Open / Reveal in Finder / Quick Look / Move to Trash

### 6.4 키보드
- 패널 열린 상태에서 ESC: 닫기
- Space: 선택 셀 Quick Look (NSPanel이 firstResponder를 가져야 함 — `becomesKey` 처리 필요)
- ↑↓←→: 셀 이동 (1차에서는 생략 가능)

---

## 7. 구현 단계 (마일스톤)

각 단계는 끝나면 직접 확인 가능한 결과물을 둠.

### M1. 프로젝트 부트스트랩 — *반나절*
- Xcode 신규 App 프로젝트 (macOS, SwiftUI Lifecycle, App, no Document)
- `Info.plist`에 `LSUIElement = YES` 추가 → Dock 아이콘 사라짐
- AppDelegate에 NSStatusItem 등록, 클릭 시 console 로그
- **확인:** 빌드/실행하면 상태바에 아이콘 뜨고, 메인 윈도우는 안 뜸

### M2. 패널 띄우기 (드래그 친화 NSPanel) — *반나절*
- `PanelController`: borderless nonactivating NSPanel을 상태바 버튼 아래에 위치
- NSHostingView로 더미 SwiftUI 뷰(`Text("hello")`) 호스팅
- 외부 클릭/ESC 시 hide
- **확인:** 아이콘 클릭하면 텍스트 박스가 뜨고, 다른 곳 클릭하면 닫힘. 박스 안에서 드래그 동작 시 닫히지 않음(이 시점은 더미)

### M3. Desktop 파일 목록 표시 — *1일*
- `DesktopStore.refresh()`: FileManager로 `~/Desktop` 읽고 mtime DESC 정렬
- `.DS_Store`, dotfile 제외
- ContentView: 일단 리스트로 파일명만 표시
- 권한 트리거: 첫 디렉터리 접근 시 macOS가 동의 다이얼로그 자동 표시 (`NSDesktopFolderUsageDescription` 필요)
- **확인:** 패널 열면 Desktop 파일 이름이 최신순으로 보임

### M4. 썸네일 — *1일*
- `ThumbnailCache`: 키 = `URL + mtime`, NSCache 용량 50MB 정도
- `QLThumbnailGenerator`로 비동기 요청, 완료 시 NSCache 저장 + Publisher 통해 뷰 갱신
- 폴백: 시스템 아이콘 (`NSWorkspace.shared.icon(forFile:)`)
- ContentView를 LazyVGrid + FileGridItem으로 전환
- **확인:** 스크린샷·동영상·PDF 썸네일이 정상적으로 보임

### M5. 드래그 앤 드롭 — *반나절* (가장 중요)
- `FileGridItem`에 `.onDrag { NSItemProvider(contentsOf: url)! } preview: { thumbnail }`
- 드래그 시작 시 패널이 닫히지 않는지 확인 (M2에서 검증한 NSPanel + nonactivating 덕분에 OK여야 함)
- **확인 시나리오 (반드시 직접 테스트):**
  1. Desktop 스크린샷을 패널에서 GitHub PR 코멘트창으로 드래그 → 업로드됨
  2. Finder의 새 폴더로 드래그 → 파일이 이동/복사
  3. Slack 입력창으로 드래그 → 첨부됨
  4. 메일 앱 본문으로 드래그 → 첨부됨

### M6. 실시간 갱신 — *반나절*
- `DesktopFolderObserver`: kqueue로 `~/Desktop` 디렉터리 감시
- write/extend/rename/delete 이벤트 → 200ms debounce → `store.refresh()`
- **확인:** 패널 열어둔 상태에서 `Cmd+Shift+4`로 스크린샷 찍으면 1초 안에 그리드에 등장 + 맨 위

### M7. 셀 컨텍스트 메뉴 & 더블클릭 — *반나절*
- `.contextMenu` — Reveal in Finder / Open / Quick Look / Move to Trash
- 더블클릭 = Open
- Quick Look: `QLPreviewPanel.shared()` 사용
- **확인:** 각 메뉴 항목 동작

### M8. 폴리시 & QA — *반나절*
- 상태바 아이콘 디자인 (Template asset)
- 패널 애니메이션 / 그림자
- 다크 모드 색 검수
- 빈 상태, 권한 거부 상태 UI
- 첫 실행 시 권한 안내 토스트
- 메모리 leak 점검 (Instruments)

**총 예상: 4~5일 (집중 시)**

---

## 8. 위험요소 & 대응

| 위험 | 영향 | 대응 |
|------|------|------|
| 드래그 시 패널이 닫혀 드래그 세션이 끊김 | 핵심 기능 불능 | NSPanel + nonactivating으로 시작. 만약 그래도 발생하면 패널을 statusBar window level로 올리고 mouseDown 외부 모니터를 드래그 중에만 일시 해제 |
| Desktop 폴더 권한 거부 | 빈 화면만 표시 | 권한 미부여 감지 시 안내 + "시스템 설정 열기" 버튼 |
| 대량 파일 시(500+) 썸네일 부하 | UI 버벅임 | LazyVGrid는 가시영역만 렌더 + 썸네일 비동기 + onAppear에서 요청 |
| `.DS_Store` 같은 가짜 변경 이벤트로 잦은 갱신 | 배터리/CPU | 200ms debounce + dotfile 무시 |
| QLThumbnailGenerator가 일부 파일 타입에서 실패 | 빈 셀 | 시스템 아이콘으로 폴백 |
| 다중 디스플레이/메뉴바 위치(상단 노치) | 패널이 잘못된 위치 | NSStatusItem.button.window.convertToScreen으로 절대 좌표 계산 |

---

## 9. 검증 체크리스트 (M5·M6 통합)

- [ ] 스크린샷 새로 찍기 → 1초 안에 맨 위에 뜬다
- [ ] 패널 → **github.com PR 첨부 영역**으로 드래그 → 파일 업로드 성공 (이게 본 프로젝트 존재 이유)
- [ ] 패널 → Finder 폴더로 드래그 → 정상 복사/이동
- [ ] 패널 → Slack 채팅 입력창으로 드래그 → 첨부됨
- [ ] 드래그 중 패널이 닫히지 않는다
- [ ] Cmd+Q 또는 우클릭 Quit으로 깨끗하게 종료
- [ ] 재로그인/재부팅 후에도 권한 유지 (선택: "로그인 항목 추가"는 후순위)
- [ ] 활성 화면이 멀티 디스플레이여도 상태바 버튼 아래에 정확히 위치

---

## 10. 다음 단계 (이 계획 승인 시)

1. `M1` 프로젝트 부트스트랩부터 진행
2. 각 마일스톤 끝마다 직접 동작 확인 후 다음 단계
3. M5(드래그) 완료 후 GitHub에 실제 PR 첨부 시도 → 본 도구의 PoC 성공 판정

승인하시면 M1부터 착수하겠습니다. 변경하고 싶은 항목 있으시면 말씀해 주세요 (예: macOS 최소 버전, 패널 너비, 부가 기능 범위 등).
