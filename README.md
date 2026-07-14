# rpi3-nixos — Raspberry Pi 3 공유 프린터 서버

Raspberry Pi 3에 NixOS를 올려 USB 프린터(Samsung Xpress M2020)를 네트워크 공유 프린터로 운영하기 위한 설정 저장소입니다. CUPS + Avahi(mDNS) 조합으로 내부망 기기에서 자동 발견되고, Tailscale로 외부에서도 인쇄할 수 있습니다.

## 구성 파일

| 파일 | 설명 |
|---|---|
| `flake.nix` | aarch64-linux 크로스 빌드용 플레이크. `nixosConfigurations.rpi3-print` 정의 |
| `configuration.nix` | 시스템 본체 설정 — SSH, 방화벽, Tailscale, CUPS, Avahi, 프린터 자동 등록 |
| `flake.lock` | nixpkgs(nixos-unstable) 핀 고정 |
| `rpi-print.crt` | CUPS 자체 서명 **공개** 인증서 (개인키 없음). HTTPS(631)로 접속하는 클라이언트가 신뢰시킬 때 사용 |

## 주요 설정 내용

- **호스트명**: `rpi3-print` → mDNS로 `rpi3-print.local` 접근
- **CUPS**: 631 포트, 프린터 기본 공유, dnssd 브로드캐스트. 접근은 내부망(`@LOCAL`)과 Tailscale 대역(`100.64.0.0/10`)만 허용
- **SSH**: root 공개키 로그인만 허용 (`prohibit-password`, 비밀번호 인증 비활성)
- **Tailscale**: 활성화됨. 첫 부팅 후 기기 인증 필요 (아래 참고)
- **프린터 자동 등록**: 부팅 시 `register-printer` systemd 서비스가 `lpadmin`으로 큐를 등록/갱신. 프린터가 꺼져 있어도 큐가 멈추지 않도록 `printer-error-policy=retry-job` 적용

## 프린터 드라이버에 대해

Samsung Xpress M2020은 **SpliX**(오픈소스 SPL/QPDL 드라이버)의 **ML-2160 PPD**로 구동합니다 (`samsung/ml2160.ppd`).

- 삼성 공식 ULD(Unified Linux Driver)는 **x86 바이너리 전용**이라 aarch64(RPi)에서는 실행 자체가 불가능합니다. nixpkgs의 `samsung-unified-linux-driver`도 i386/x86_64 바이너리만 설치합니다.
- 과거 nixpkgs의 splix 정식 릴리스(2.0.0) PPD에는 `QPDLVersion`이 빠져 있어 M2020 계열에서 인쇄가 깨지는 문제가 있었습니다([NixOS/nixpkgs#36876](https://github.com/NixOS/nixpkgs/issues/36876)). 현재 nixpkgs는 커뮤니티 수정이 포함된 SVN 스냅샷(r315)으로 빌드하며, PPD에 `*QPDL QPDLVersion: "3"`이 포함되어 있어 해결된 상태입니다.

## 빌드 및 배포

### 사전 조건: x86 PC에서 aarch64 빌드

이 플레이크는 aarch64-linux 시스템을 정의하므로, x86_64 PC에서 빌드하려면 QEMU 바이너리 에뮬레이션이 필요합니다.

- Arch Linux: `qemu-user-static` + `qemu-user-static-binfmt` 설치
- `/etc/nix/nix.conf`에 `extra-platforms = aarch64-linux` 추가
- 확인: `ls /proc/sys/fs/binfmt_misc/ | grep aarch64` 에 `qemu-aarch64`가 보여야 함

> 참고: 저장소가 git이므로 새 파일은 `git add` 되어 있어야 플레이크 평가에 포함됩니다.

### 최초 설치 — SD 카드 이미지

```bash
nix build .#nixosConfigurations.rpi3-print.config.system.build.sdImage
zstd -d result/sd-image/*.img.zst -o rpi3.img
sudo dd if=rpi3.img of=/dev/sdX bs=4M status=progress conv=fsync
```

> `/dev/sdX`는 반드시 `lsblk`로 SD 카드 디바이스인지 확인 후 실행하세요.

### 설정 변경 후 — SSH 원격 배포 (SD 재작성 불필요)

Pi가 부팅되어 있으면 **이 PC에서 빌드해서** SSH로 밀어 넣고 즉시 전환합니다. RPi3는 RAM 1GB라 자체 빌드가 너무 오래 걸리므로, `--build-host`를 지정하지 않는 아래 형태(로컬 빌드)를 유지하세요:

```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#rpi3-print --target-host rpi3
```

- `rpi3`는 `~/.ssh/config`의 SSH 별칭입니다 (`HostName 192.168.0.131`, `User root`). 별칭이 없는 환경에서는 `--target-host root@rpi3-print.local`을 쓰면 됩니다.
- 평가 단계에서 새 파일이 안 보인다는 오류가 나면 `git add`가 빠진 것입니다 (git 저장소의 플레이크는 추적된 파일만 봅니다). `--impure`는 필요 없습니다.

동작 순서:

1. **로컬 빌드** — x86 PC에서 QEMU 에뮬레이션으로 aarch64 시스템 클로저를 빌드합니다. 대부분 공식 바이너리 캐시에서 다운로드됩니다.
2. **클로저 복사** — 변경된 스토어 경로만 SSH로 Pi에 복사합니다.
3. **전환** — Pi에서 `switch-to-configuration switch`가 실행되어 바뀐 서비스만 재시작됩니다. 재부팅 불필요.

유용한 변형:

```bash
# 재부팅 후에만 적용 (다음 부팅부터 새 설정)
nix run nixpkgs#nixos-rebuild -- boot --flake .#rpi3-print --target-host rpi3

# 테스트 적용 (재부팅하면 이전 설정으로 복귀)
nix run nixpkgs#nixos-rebuild -- test --flake .#rpi3-print --target-host rpi3
```

문제가 생겼을 때 롤백:

```bash
ssh rpi3 nixos-rebuild switch --rollback
# 또는 부팅 시 extlinux 메뉴에서 이전 세대(generation) 선택
```

nixpkgs 버전 올리기:

```bash
nix flake update && nix eval .#nixosConfigurations.rpi3-print.config.system.build.toplevel.drvPath
```

## Tailscale 설정 (외부 접속)

최초 1회, Pi에서 tailnet 인증:

```bash
ssh root@rpi3-print.local tailscale up
# 출력된 URL을 브라우저에서 열어 로그인
```

이후 외부에서:

- SSH: `ssh root@rpi3-print` (MagicDNS) 또는 Tailscale IP
- 인쇄: `ipp://rpi3-print.<tailnet-이름>.ts.net:631/printers/Samsung_M2020`
- 웹 관리: `http://rpi3-print.<tailnet-이름>.ts.net:631`

> mDNS(자동 발견)는 멀티캐스트라 Tailscale을 통과하지 않습니다. 원격 클라이언트에서는 위 IPP 주소로 수동 등록해야 합니다. 필요하면 Tailscale ACL에서 631 포트를 특정 기기로 제한할 수 있습니다.

## 클라이언트에서 프린터 사용

**클라이언트에는 삼성 드라이버도 PPD도 필요 없습니다.** QPDL 변환은 Pi가 하므로, 클라이언트는 IPP Everywhere(드라이버리스)로 붙으면 됩니다. 드라이버 선택 화면에서 "Samsung"이나 "ML-2160"을 찾지 마세요 — 안 뜨는 게 정상입니다.

- **Linux (CUPS)** — 한 줄 등록:

  ```bash
  sudo lpadmin -p Samsung_M2020 -v ipp://rpi3-print.local:631/printers/Samsung_M2020 -m everywhere -E
  ```

  또는 CUPS 웹 UI(localhost:631)에서 발견된 프린터 추가 시 드라이버 목록에서 **"IPP Everywhere"** 선택. `cups-browsed`가 돌고 있으면 공유 큐가 자동으로 로컬에 나타나기도 합니다.
- **macOS**: 프린터 추가에서 자동 발견 → 드라이버는 "Secure AirPrint/IPP" 기본값 그대로.
- **Windows**: 프린터 추가 → `http://rpi3-print.local:631/printers/Samsung_M2020`
- **CUPS 웹 관리**: <http://rpi3-print.local:631> — 단, **설정 변경(관리 작업)은 불가**합니다. NixOS root에 비밀번호가 없어 인증(401)이 안 되기 때문이며, 큐 관리는 SSH에서 `lpadmin`으로 하세요.

HTTPS 접속 시 인증서 경고가 뜨면 `rpi-print.crt`를 클라이언트 신뢰 저장소에 추가하면 됩니다.

## 트러블슈팅

인쇄가 안 될 때 Pi에서 순서대로 확인:

```bash
lsusb | grep -i samsung          # 1. USB에서 프린터가 보이는가? (안 보이면 전원/케이블 문제)
lpinfo -v | grep usb             # 2. CUPS가 USB 프린터를 인식하는가?
lpstat -t                        # 3. 큐 상태와 대기 작업 확인
journalctl -u register-printer   # 4. 큐 등록 서비스 로그
tail -f /var/log/cups/error_log  # 5. 인쇄 시도하며 CUPS 로그 관찰
```

- 큐는 있는데 `lpinfo -v`에 USB 장치가 없으면 **프린터 전원이 꺼졌거나 케이블 문제**입니다. 소프트웨어 설정과 무관합니다.
- `printer-error-policy=retry-job`이 적용되어 있으므로 프린터를 켜면 대기 중이던 작업이 자동으로 재시도됩니다.
- 인쇄물이 깨져 나오면 PPD를 확인하세요: `grep QPDL /etc/cups/ppd/Samsung_M2020.ppd`에 `QPDLVersion: "3"`이 있어야 정상입니다.

### 주의: CUPS 웹 UI로 설정을 저장하지 마세요

웹 UI에서 "Edit Configuration File"이나 "Allow remote access" 같은 설정을 저장하면 cupsd가 `/var/lib/cups/cupsd.conf`를 **일반 파일로 덮어씁니다**. NixOS cups 모듈은 이 파일이 이미 존재하면 건드리지 않기 때문에, 이후 `configuration.nix`의 CUPS 설정이 전부 무시됩니다 (실제로 2026-07-09에 이 문제가 발생했었음). 복구 방법:

```bash
ssh rpi3 'rm /var/lib/cups/cupsd.conf && systemctl restart cups.service'
```

재시작 시 스토어의 선언적 설정으로 심링크가 다시 걸립니다. 프린터 추가/삭제 같은 큐 조작은 웹 UI를 써도 무방합니다 (`printers.conf`는 원래 가변 상태 파일).

## 보안

이 저장소는 공개해도 안전합니다 — SSH 키는 공개키이고, `rpi-print.crt`는 개인키 없는 공개 인증서입니다.

적용된 보안 설정:

- SSH: 공개키 인증만 허용 (`PermitRootLogin = "prohibit-password"`, `PasswordAuthentication = false`)
- CUPS: `@LOCAL`(내부망) + Tailscale IPv4(`100.64.0.0/255.192.0.0`) + Tailscale IPv6(`[fd7a:115c:a1e0::]/48`)만 허용. CUPS의 `@LOCAL`은 point-to-point 인터페이스를 제외하므로 Tailscale 대역은 명시적으로 추가해야 합니다. 100.64/10은 공인 인터넷에서 라우팅되지 않는 CGNAT 대역이고, 그 트래픽이 들어오는 유일한 경로인 `tailscale0`은 tailnet 기기 인증을 거친 트래픽만 통과시킵니다.
- 방화벽: 631(TCP/UDP), SSH(22), Tailscale(UDP 41641)만 개방. `tailscale0`은 신뢰 인터페이스

**cupsd `Allow` 문법 함정 (실측 확인, CUPS 2.4.19):**

- `Allow 100.64.0.0/10` 같은 **CIDR 표기는 매칭되지 않습니다** — 점 표기 넷마스크(`100.64.0.0/255.192.0.0`)를 써야 합니다.
- IPv6 대역은 대괄호 필수: `Allow [fd7a:115c:a1e0::]/48` (대괄호 없으면 무효).
- `Allow @IF(tailscale0)`는 그 인터페이스에 붙은 /32 주소만 매칭해서 원격 tailnet 피어에는 소용없습니다.
- Tailscale MagicDNS(`*.ts.net`)는 IPv6를 우선 사용하는 클라이언트가 많으므로 IPv4 대역만 허용하면 403이 납니다.
