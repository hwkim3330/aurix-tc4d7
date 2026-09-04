# 굽는 경로 (미해결 — 이 프로젝트의 실질적 관문)

**빌드가 되는 것과 보드에서 돌아가는 것은 다르다.** 툴체인을 다 확보해도 여기가 막히면
아무것도 실행할 수 없다. 순서상 툴체인보다 **먼저** 뚫어야 하는 문제다.

## 왜 막혔는가

벤더 Zephyr 의 보드 정의:

```cmake
# ws/zephyr/boards/infineon/kit_a3g_tc4d7_lite/board.cmake
board_set_flasher_ifnset(winidea)
board_finalize_runner_args(winidea)
```

flash runner 가 **iSYSTEM winIDEA** — 상용 도구이고 Windows 다. 즉 `west flash` 는
Linux 에서 바로 안 된다.

그리고 Infineon 공식 디버그 서버 **DAS 는 Windows 전용**이다.

## 후보 (유망한 순서)

### 1. ASC BSL / Generic BSL over `/dev/ttyUSB0` ★ 최우선

**핵심**: 부트스트랩 로더가 쓰는 UART 핀이 이미 USB 로 나와 있다.

| HWCFG[3..4] | 부트 타입 | 핀 | R73 | R74 | R75 | R76 |
|---|---|---|---|---|---|---|
| `00` | **Generic BSL (CAN/ASC)** | **P14.0 / P14.1** | NA | A | NA | A |
| `10` | ASC BSL | P15.2 / P15.3 | A | NA | NA | A |
| `X1` | BMHD 에서 시작 (미프로그램이면 HARR 또는 generic BSL 폴백) | — | x | x | A | NA |

- HWCFG[3] = **P14.3**, HWCFG[4] = **P10.5** (유저 가이드 Table 12)
- **P14.0 / P14.1 = ASCLIN0 = FT2232H 채널 B = `/dev/ttyUSB0`**
- 즉 **추가 하드웨어 없이 USB 케이블만으로 BSL 에 말을 걸 수 있다**

`A` = 장착, `NA` = 미장착, `x` = don't care.

**확인해야 할 것**:
- 공장 출하 시 R73~R76 조합이 무엇인지 (유저 가이드가 각 모드별 조합만 주고 기본값을 명시하지
  않는다). 정상 동작용이므로 `X1`(BMHD) 로 추정되지만 **미확인**
- BMHD 가 프로그램되지 않은 새 보드면 **generic BSL 로 폴백**한다고 문서에 있다 →
  공장 출하 상태에서 이미 BSL 이 떠 있을 가능성이 있다
- BSL 프로토콜(프레임 포맷, 명령, 체크섬) 문서. TC3xx BSL 문서가 TC4x 에도 적용되는지 확인 필요
- 보레이트

**검증 방법**: `scripts/40-bsl-probe.py`. ASC BSL 은 보레이트를 자동 검출하므로 수동 청취로는
아무것도 안 나오는 게 정상이고, 호스트가 먼저 말을 걸어야 ACK 가 돌아온다.

#### 측정 결과 (2026-09-04) — 응답 없음

| 시도 | 조건 | 결과 |
|---|---|---|
| 수동 청취 | 9600 ~ 500000 baud, 각 0.6 s | 전 보레이트 무음 |
| 능동 프로브 1바퀴 | `00` / `55` / `aa` / `0000` × 8 보레이트 | 무응답 |
| 능동 프로브 120 s (14바퀴) | 위와 동일, 반복 | 무응답 |

**해석 (미확정)**: 120초 구간에 리셋이 실제로 눌렸는지 확인되지 않았다. 따라서 두 가설이
아직 살아 있다:

1. 리셋이 안 눌렸다 → BSL 창을 놓쳤을 뿐이고 재시도하면 된다
2. 리셋이 눌렸는데도 무응답 → **부트 모드가 BSL 이 아니다.** `R73`~`R76`(0603) 을 인두로
   옮겨 `HWCFG[3..4]` 를 `00` 으로 바꿔야 한다

가설 2가 맞으면 이 경로의 비용이 "케이블만"에서 "리워크"로 뛴다. 재시도 시
**프로브를 먼저 띄우고 몇 초 뒤 리셋을 누르는** 순서로 가설 1을 먼저 배제할 것.

참고: `/PORST` 는 miniWiggler 의 FT2232HL **ACBUS1**(채널 A)에 걸려 있고 `ttyUSB0` 는
채널 B 다. 따라서 호스트에서 소프트웨어로 리셋을 걸 수 없다 — 사람이 눌러야 한다.
(다른 리셋 소스: RESET 버튼, DAP pin 10, Arduino X302.3, 핀헤더 X1.30)

> 참고: `R14`/`R15`(0 Ω, 미장착)를 장착하면 USB UART 가 ASCLIN0(P14.0/P14.1) 대신
> **ASCLIN11(P21.0/P21.1)** 로 바뀐다. 이 경우 BSL 핀과 USB UART 가 분리되므로
> **장착하지 말 것**.

### 2. Infineon TAS Tool Interface + aurix-openocd

- DAS 와 달리 **TAS 는 Linux 서버 바이너리가 있다** (`sudo TAS_V*/bin/tas_server`)
- `aurix-openocd` 와 조합해 TC3xx 를 구운 블로그 사례가 존재
- **TC4x 실증을 찾지 못했다.** TriCore 1.6.2P → 1.8P 로 코어 세대가 다르고 DAP 도 다를 수 있다
- 온보드 miniWiggler(FT2232H)에 FTDI 드라이버가 필요한데 Linux 는 `ftdi_sio` 가 이미 붙는다
  (채널 B). 채널 A 를 TAS 가 잡으려면 `ftdi_sio` 언바인드가 필요할 수 있다

### 3. Infineon MemTool

miniWiggler 와 함께 쓰도록 만들어진 플래시 도구. **Windows 전용으로 보인다.** 미확인.

### 4. DAP over FT2232H 직접 구동

miniWiggler 채널 A 를 직접 두들긴다. DAS 프로토콜을 리버싱해야 하므로 **비용이 가장 크다.**
1~3 이 모두 실패한 경우의 마지막 수단.

## 현실적 대안 — Windows 박스

`board.cmake` 가 지정하는 winIDEA, 또는 AURIX Development Studio + DAS 를 쓰면
**이 관문은 존재하지 않는다.** Windows 머신이 있다면 그쪽이 압도적으로 빠르다.

Linux 에서 끝까지 가야 할 이유가 없다면 이게 정답이다. 이 문서는 "Linux 로만 가겠다"는
제약을 유지할 때의 경로를 정리한 것이다.

## 결론

**후보 1(BSL over ttyUSB0)만 조사 비용이 낮다.** 나머지는 실증 없는 도구 조합이거나
리버싱이다. 이 프로젝트를 재개한다면 **툴체인 빌드보다 후보 1 검증을 먼저** 해야 한다 —
여기가 막히면 툴체인 빌드는 버려지는 시간이다.
