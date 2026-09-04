# 이 보드에 걸리는 실리콘 결함 (GETH / 이더넷)

출처: [AURIX TC4Dx errata sheet, Marking/Step **(E)ES-AB**, v1.0, 2025-06-18](https://www.infineon.com/assets/row/public/documents/10/52/infineon-aurix-tc4dx-ab-es-erratasheet-en.pdf)

**전제**: 보드에 실장된 칩이 AB 스텝인지 확인해야 한다. Infineon 부품 페이지가
`SAK-TC4D7XP-20MF500MC-AB` 를 판매 중이므로 AB 로 가정하지만, **칩 마킹으로 확인 필요**.

## 요약: 100 Mbps 는 "느려서" 문제가 아니다

속도 여력은 충분하다([hardware.md](hardware.md) 참조). 문제는 **트래픽 제너레이터가 팔아야 할
바로 그 정밀도**(IPG, CBS, TAS)가 결함으로 깎여 있다는 것이다.

특히 **`GETH_AI.034` / `GETH_AI.039` 는 스코프가 "10/100 Mbps MII speed modes" 로,
이 보드의 유일한 동작 모드를 정확히 겨냥한다.**

---

## 10/100 MII 모드 전용 결함

### `GETH_AI.034` — 프로그램한 IPG 와 실제 최소 IPG 불일치

MII speed mode 에서 IPG 필드가 **8-bit times 가 아니라 4-bit times 로 잘못 해석**된다.

```
IFP = 1 →  minIPG = 24 + ({EIPG,IPG} * 4)
IFP = 0 →  minIPG = 24 - IPG
```

- 예: IFP=0, EIPG=0, IPG=2 → minIPG 22 = **88 bit times** (기대 80)
- **홀수를 넣으면 8-bit times 정수배가 아니게 되어 표준 위반**

**스코프**: GETH 가 10 또는 100 Mbps MII speed mode 이고 `Portj_MAC_Tx_Configuration` 의
IPG 필드가 0 이 아닐 때.

**우회**: IPG 필드에 **짝수만**, 그리고 **원하는 인코딩 값의 2배**를 넣는다.
→ 쓸 수 있는 minIPG 값의 해상도가 절반으로 준다.

### `GETH_AI.039` — MII 언더플로 시 패킷이 종료되지 않고 손상

TXQ 언더플로가 나면 정상적으로는 패킷을 종료해야 하는데, MII 모드(10/100)에서는
**이전 32비트 워드를 반복 전송**한다.

- 그 뒤 다음 유효 데이터가 있으면 나머지도 전송되고 → **패킷 손상**
- 없으면 언더플로로 종료 → 영향은 1 워드 반복에 한정

**우회**: TXQ 를 **store-and-forward 모드**로 운용하고,
패킷 크기를 `TXQ_SIZE(byte) - ((PBL + 5) * 8)` 이하로 제한.

---

## TSN 기능 결함 (속도 무관)

### `GETH_AI.029` — CBS 크레딧이 IPG 구간에 감소하지 않음 ⚠️

802.1Qav 는 preamble / FCS / 최소 IPG(12 B) 같은 오버헤드 구간에도 크레딧을 감소시켜야 한다.
그런데 MAC 은 **패킷 데이터 마지막 바이트(FCS)까지만 감소시키고, 그 뒤 nominal IPG 구간에는
크레딧을 증가**시킨다.

**결과: 해당 TC 가 프로그램한 대역폭보다 더 먹는다.**

```
추가 대역폭 = ((패킷수 × 12 B) / (해당 윈도우 총 전송 바이트, preamble 포함)) × 프로그램한 FractionalBW
```

errata 문서의 예: 128 B 패킷 100개에 30% 를 주면 → 추가 2.65% → **실제 32.65%**

**우회**: 목표보다 **낮은 값으로 프로그램해서 보정**한다. 보정량은 평균 패킷 길이에 의존하는
추정치다.

> **이 칩을 CBS 레퍼런스/검증 기준으로 쓰면 안 된다.** LAN9662 / 9692 의 CBS 를 검증하는
> 기준점으로 삼으면 기준 자체가 틀어진다.

### `GETH_AI.032` — TAS(EST)에서 back-to-back 전송 시 추가 IPG ⚠️

EST 활성 시 Transmit Scheduler 가 현재 패킷이 MAC Transmitter 로 완전히 넘어갈 때까지 다음
패킷 스케줄링을 미루는데, fGETH ↔ MAC Transmitter 클럭 도메인 간 CDC 지연 때문에
**프로그램한 최소 IPG 보다 큰 추가 IPG** 가 발생한다.

- 최악 **두 클럭 중 느린 쪽의 12 사이클** (두 클럭의 주파수·위상 관계에 따라 달라짐)
- errata 예시는 1 Gbps 기준: 8 ns × 12 = **96 ns/패킷**
- 100 Mbps 에서의 값은 UM 에서 fGETH 와 MAC Transmitter 클럭 실제 주파수를 확인해야 한다.
  (MAC TX 가 25 MHz 라면 40 ns × 12 = 480 ns/패킷 → 64 B 프레임 6.72 µs 대비 약 7% —
  **이건 내 추정이고 미검증**)

**영향**: GCL 의 한 Time Interval(슬롯) 안에 넣을 수 있는 패킷 수가 줄고, 예상 시각보다 늦게
도착한 패킷을 원단이 버릴 수 있다.

**우회**: 슬롯에 넣을 패킷 수를 감안해 **TI 를 추가 IPG 만큼 늘려서** 프로그램한다.

> **결정적**: errata 문서가 명시한다 — *"there is no workaround to guarantee minimum IPG
> between transmission of back to back packets in the same time slot."*
> 즉 **같은 슬롯 안 back-to-back 프레임의 최소 IPG 를 보장할 방법이 없다.**
> 정밀 트래픽 제너레이터로서는 이게 가장 아픈 항목.

### `GETH_AI.042` — 수신 타임스탬프를 끄면 RX 프레임이 정지

조건: untagged 패킷이 ingress MAC 으로 들어와 RxDMA 로 라우팅되고 **수신 타임스탬프가 비활성**.

**영향**: 같은 RxQ 를 여러 RxDMA 에 매핑한 경우 head-of-line blocking.

**우회**: `MAC_Timestamp_Control.TSENALL = 1` — **모든 수신 패킷에 타임스탬프 켜기**.
→ 우리 용도(하드웨어 타임스탬프로 지연 측정)에는 어차피 필요하므로 **무해**.

### `GETH_AI.040` — 컨텍스트 디스크립터 미완료로 RX DMA 스톨

조건 전부 충족 시: 프레임이 host(RxDMA)와 다른 egress 포트로 **동시 복제** + 포워딩 경로의
RXC 채널 번호가 RxDMA 채널의 RXC 보다 큼 + ingress 패킷이 **VLAN 태그** + **수신 타임스탬프 활성**.

**우회**: Bridge 모드에서 ingress 패킷의 브리지 포워딩 복제를 **모든 RxDMA 복제가 끝난 뒤 한 번만**
하도록, 복제 대상 채널 중 **가장 낮은 RXC** 를 포워딩 채널로 매핑한다.

### `GETH_AI.041` — 패킷 길이 변동 + Tx DMA 활성 시 RX DMA 스톨

조건: 타임스탬프 전체 활성 + **TxDMA PBL > 8** + ingress 를 포워딩과 RxDMA 양쪽에 매핑.

**우회**: **TxDMA PBL ≤ 8**.

### `GETH_AI.045` — 브리지가 포워딩 패킷에 8 바이트를 덧붙임

조건: 포워딩 트래픽 소버스트 뒤 SOF 를 담은 RxDMA 버스트 + 같은 egress 포트로 동시 TX DMA 버스트.

**영향**: 8 바이트 패딩. egress MAC 이 CRC 를 재계산하므로 **FCS 에러나 드롭은 나지 않는다**
(= 조용히 프레임 길이가 틀어진다).

**우회**: TXQ 로 밀 때 **TxDMA PBL ≤ 4 beats**.

> `GETH_AI.041`(PBL ≤ 8)과 `GETH_AI.045`(PBL ≤ 4)를 함께 만족시키려면 **PBL ≤ 4**.

---

## 이 보드에 해당하지 않는 것

- **`HSPHY_TC.005`** (온도 변화 시 수신 이더넷 링크 상실) — **SGMII / USXGMII** PHY 얘기다.
  이 보드는 5 Gbps 포트를 뽑지 않으므로 해당 없음
- **`LETH_*`** 계열 (10BASE-T1S PLCA 등 다수) — LETH 컨트롤러 얘기. 보드 RJ45 는 GETH0 Port0

## 참고할 만한 인접 항목

- `DRE_TC.H002` — GETH → LETH / LETH → LETH 포워딩 시 **throughput 성능 저하** (application hint)
- `DRE_TC.006` — GETH 와 LETH 의 에러 인터럽트 트리거 불일치
- `GETH_AI.033` — 수신 패킷이 프로그램한 VLAN filter fail 큐로 라우팅되지 않음
  (우회: Rx status 의 VLAN filter fail 비트를 소프트웨어가 직접 확인)
- `GETH_AI.036` — 임계 바이트 수가 차기 전에 MAC 이 전송을 시작
- `SAFETY_TC.032` — `GETH:ISR_MONITOR` 레지스터 이름 오기 (문서 오류)
- `CANXL_AI.001` — TX priority queue slot 0-7 사용 시 **Tx 메시지 순서가 틀림** (CAN XL 쓸 때 확인)
