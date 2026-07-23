{ pkgs, pkgsX86, ... }:

# 프린터 서버 역할. Samsung Xpress M2020을 USB로 물려 CUPS로 공유한다.
# 이 파일만 빼면 순수 기반 시스템으로 돌아가도록 프린터 관련 설정을 여기 모은다.
# (자세한 드라이버/네트워크 함정은 README 참고)

{
  # 프린트 필터가 텍스트 문서를 렌더링할 때 필요한 폰트. 헤드리스라 이 용도뿐이다.
  fonts = {
    packages = with pkgs; [
      dejavu_fonts
      freefont_ttf
      liberation_ttf
    ];
    fontconfig.enable = true;
  };

  # 삼성 ULD의 rastertospl(x86_64 바이너리)을 qemu로 실행하기 위한 에뮬레이션
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

  # CUPS(IPP) 포트. base의 trustedInterfaces와 별개 속성이라 그대로 병합된다.
  networking.firewall.allowedTCPPorts = [ 631 ];
  networking.firewall.allowedUDPPorts = [ 631 ];

  # 3. 프린터 서버 설정
  services.printing = {
    enable = true;
    drivers = [
      pkgs.foomatic-db
      pkgs.cups-filters
      pkgs.gutenprint
      # M2020의 실제 드라이버. x86_64 전용 rastertospl은 binfmt(qemu)로 돈다.
      # splix(ml2160.ppd)는 M2020 펌웨어를 크래시시키므로 제외 — README 참고.
      pkgsX86.samsung-unified-linux-driver_1_00_36
    ];
    listenAddresses = [ "*:631" ];
    defaultShared = true;
    browsing = true;
    # NixOS 모듈이 이 목록으로 <Location />, <Location /admin> 등의 Allow 규칙을 생성한다.
    # @LOCAL = 내부망. Tailscale 대역은 IPv4(100.64/10 CGNAT)와 IPv6(fd7a:115c:a1e0::/48) 둘 다 필요
    # — MagicDNS는 IPv6를 우선하는 클라이언트가 많다.
    # 실측 주의사항 (실제 tailnet 클라이언트로 검증함):
    #  - cupsd는 "100.64.0.0/10" CIDR 표기를 매칭하지 못함 → 점 표기 넷마스크 필수
    #  - "@IF(tailscale0)"는 인터페이스의 /32 주소만 매칭해서 원격 피어에는 무효
    allowFrom = [ "@LOCAL" "100.64.0.0/255.192.0.0" "[fd7a:115c:a1e0::]/48" ];
    extraConf = ''
      BrowseLocalProtocols dnssd
    '';
  };

  # CUPS의 mDNS(DNS-SD) 프린터 광고용. publish.addresses 덕에 rpi3-print.local
  # SSH 접속 이름 해석도 함께 제공된다.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  # lsusb — USB 프린터 연결 상태 진단용
  environment.systemPackages = with pkgs; [
    usbutils
  ];

  systemd.services.register-printer = {
    description = "Register Samsung M2020 Printer on boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "cups.service" ];
    serviceConfig = {
      Type = "oneshot";
      # lpadmin은 기존 큐가 있어도 설정을 갱신하므로 매번 실행해 변경 사항을 반영한다.
      # 드라이버는 ULD의 M2020 전용 PPD(rastertospl/SPL). splix QPDL은 펌웨어 크래시 유발.
      # retry-job: 프린터 전원이 꺼져 있어도 큐가 멈추지 않고 재시도한다.
      ExecStart = pkgs.writeShellScript "register-printer" ''
        ${pkgs.cups}/bin/lpadmin -p "Samsung_M2020" \
          -v "usb://Samsung/M2020%20Series?serial=0B2DB8GM5B002WA" \
          -m "Samsung_M2020_Series.ppd.gz" -L "Home-Office" \
          -o printer-error-policy=retry-job -E
      '';
    };
  };
}
