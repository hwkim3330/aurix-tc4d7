# 상태와 결정 (2026-09-04)

## 원래 목표와 판정

**목표**: LAN9662 / 9692 TSN 검증용 정밀 트래픽 제너레이터 (talker + 하드웨어 타임스탬프 listener)

**판정: 이 보드로는 안 된다.** 세 겹으로 막혔고 전부 우회 불가다.

1. **100 Mbps 천장 (영구)** — RJ45 하나, DP83825I 10/100, RMII. 칩의 나머지 4포트도 10/100 이고
   기가 이상인 2× 5 Gbps 는 SGMII SerDes 라 핀헤더로 못 뽑는다. 헤더에 남은 P16 은 4개뿐이라
   RGMII(12신호)도 불가 → [docs/hardware.md](docs/hardware.md)

2. **정밀도가 errata 로 깎여 있다** — errata 문서가 명시한다:
   *"there is no workaround to guarantee minimum IPG between transmission of back to back
   packets in the same time slot"* (`GETH_AI.032`). 정밀 talker 로서 팔아야 할 바로 그 속성이다.
   추가로 `GETH_AI.029` 는 CBS 가 프로그램한 대역폭보다 더 먹게 만들고(30% → 32.65%),
   `GETH_AI.034`/`GETH_AI.039` 는 **10/100 MII 모드 전용** 결함이다
   → [docs/errata.md](docs/errata.md)

3. **소프트웨어가 없다** — Zephyr 벤더 브랜치에 GETH 드라이버가 없다
   (`eth_tc4x_leth.c` = LETH 뿐, `ETH_TC4X_GETH` 는 Kconfig 심볼만 있고 소스 없음).
   보드 dtsi 에 ethernet 노드도 없다. iLLD 베어메탈로 직접 써야 하고 Qbv 공식 예제도 없다

**부수 판정**: 이 칩을 CBS/TAS 레퍼런스로 삼으면 안 된다. `GETH_AI.029`/`.032` 때문에
기준점 자체가 틀어진다.

## 관문 순서 (수정됨)

처음엔 툴체인이 첫 관문이라고 봤는데 **틀렸다. 굽는 게 먼저다.**

```
1. 굽는 경로 확보     ← 미해결. 여기가 막히면 아래는 전부 버려지는 시간
2. tricore-elf-gcc    ← prebuilt 없음, 소스 빌드 필요 (apt 의존성도 필요)
3. 앱 빌드            ← 스크립트 준비됨
4. GETH 드라이버       ← TSN 을 원한다면. 비용 가장 큼
```

**1번이 왜 막혔나**: 벤더 보드 정의의 flash runner 가 `winidea`(iSYSTEM, 상용/Windows).
DAS 도 Windows 전용. → [docs/flashing.md](docs/flashing.md)

**1번의 유일한 저비용 후보**: **BSL over `/dev/ttyUSB0`**. 부트스트랩 로더가 쓰는
P14.0/P14.1 이 곧 ASCLIN0 이고 그게 곧 `ttyUSB0` 다. 추가 하드웨어 없이 USB 케이블만으로
말을 걸 수 있다. 재개한다면 **여기부터** 봐야 한다.

## 지금 확보된 것

| 항목 | 상태 |
|---|---|
| 보드 식별 · UART 매핑 · dialout · 디스크 확인 | ✅ `scripts/00-check-env.sh` 실측 통과 |
| Zephyr 워크스페이스 (Infineon 포크 `aurix`) | ✅ `ws/`, 보드 정의 7개 코어 타깃 확인 |
| 하드웨어 사실 · errata · 툴체인 · 굽기 조사 | ✅ `docs/` |
| apt 빌드 의존성 | ❌ sudo 필요 (아래) |
| tricore-elf-gcc | ❌ |
| 보드에서 코드 실행 | ❌ |

진행하려면:

```bash
sudo apt install -y build-essential texinfo flex bison libgmp-dev libmpfr-dev libmpc-dev
pip3 install --break-system-packages -r ws/zephyr/scripts/requirements.txt
```

## 이 보드가 값싸게 주는 것

TSN 을 포기하면 남는 것:

- **CAN FD** — 벤더 dts 가 이미 완성돼 있다. `can01`(M_CAN node 1), 500 kbit/s + 데이터 2 Mbit/s,
  TLE9371 STB 를 gpio-hog 로 부팅 시 normal 모드로 내려준다. 칩은 CAN XL 20 Mbps 도 지원
  (헤더는 1개)
- **PPU** — Synopsys ARC 벡터 코프로세서. MetaWare NN 컴파일러가 TensorFlow/ONNX 를 받아
  PPU 용으로 컴파일한다. 이 칩의 유일무이한 부분. 단 툴킷 확보(등록/라이선스)가 선행이고
  아직 조사하지 않았다
- 6 코어 @500 MHz 락스텝, 20 MB flash / 10 MB SRAM, 코어당 VM 8개

단, **어느 쪽이든 굽는 문제는 그대로다.**

## 기존 Zephyr 작업(nRF52840 / Joy-Con)에서 재사용 가능한 것

이 머신의 `~/pocket-hardware/joycon2-zephyr` (XIAO nRF52840 Sense, Zephyr 3.7.3 LTS + SDK 0.16.5)
와 비교하면:

**옮겨지는 것**
- **센서 경로** — Infineon 포크에 `lsm6dsl` / `lsm6dso` 등 ST IMU 드라이버가 있고
  `i2c_aurix.c` 도 있다. Joy-Con 쪽의 `sensor_sample_fetch` / `sensor_channel_get` 코드는
  Shield2Go 나 mikroBUS 에 I2C IMU 를 물리면 **그대로 포팅된다**
- Zephyr 작업 방식 자체 (west, prj.conf, devicetree, Kconfig)
- **단계 게이팅 방법론** — Joy-Con 프로젝트에서 "stage 1/2/3 으로 나눠 싸게 확인"한 그 방식.
  여기서는 **stage 0 = 굽기 검증**이어야 한다. 그게 안 되면 나머지가 전부 무효다

**옮겨지지 않는 것**
- **BLE 전부** — TC4D7 에는 무선이 없다. SoftDevice Controller, GATT, SMP 관련 지식은 무용
- **SDK 0.16.5** — arm-zephyr-eabi 만 들어 있다. TriCore 타깃이 없다
- **워크스페이스** — Joy-Con 쪽은 Zephyr **3.7.3**, Infineon 포크는 **4.4.0**. 릴리스가 7개
  차이나는 별개 트리다. 합칠 수 없고 각자 6 GB 를 쓴다

**가장 큰 차이는 굽는 방식이다**
- XIAO: **UF2** — 리셋 더블탭 → USB 드라이브로 마운트 → 파일 드래그. 도구가 0개다
- AURIX: winIDEA(상용/Windows). Joy-Con 이 쉬웠던 이유와 이 보드가 막힌 이유가 정확히 같은 지점이다

## 재개 조건

이 중 하나가 생기면 재개할 가치가 있다:

- **Windows 박스** — winIDEA / ADS + DAS 를 쓰면 관문 1이 아예 사라진다. 가장 빠른 길
- **TriBoard TC4x9** — 5 Gbps 포트와 PCIe 를 실제로 뽑는 보드. 트래픽 젠 목표가 되살아난다
- **BSL 프로토콜 문서 확보** — 관문 1을 Linux 에서 뚫을 수 있게 된다
- **PPU 를 쓸 이유** — 온디바이스 NN 을 ASIL-D 급 MCU 에서 돌려야 할 때

## 용량

| 경로 | 크기 | 성격 |
|---|---|---|
| `ws/modules` | 5.2 GB | 대부분 TriCore 무관 (nordic/st/nxp HAL 등). west 가 관리 |
| `ws/zephyr` | 1.3 GB | Infineon 포크 |
| 레포 본체 (`ws/` 제외) | **408 KB** | ← 실제 산출물. 조사 결과는 여기 다 있다 |

`ws/` 는 gitignore 되어 있고 `scripts/20-init-workspace.sh` 로 언제든 재생성된다.
공간이 급하면 지워도 손실이 없다 — `scripts/99-disk.sh` 참조.
