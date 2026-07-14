{ config, pkgs, ... }:

{
  fonts = {
  packages = with pkgs; [
    dejavu_fonts
    freefont_ttf
    liberation_ttf
  ];
    fontconfig.enable = true;
  };
  # 1. 시스템 핵심 설정
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  networking.hostName = "rpi3-print";
  networking.networkmanager.enable = true;
  system.stateVersion = "25.05";
  networking.firewall.allowedTCPPorts = [ 631 ];
  networking.firewall.allowedUDPPorts = [ 631 ];
  # tailscale0으로 들어오는 트래픽은 tailnet 기기 인증을 이미 거쳤으므로 신뢰
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # 2. SSH 및 사용자 설정
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Tailscale — 외부에서 인쇄/관리 접속용. 첫 부팅 후 `tailscale up`으로 인증 필요.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC0jiC85gBcCkam7qsaysP99nY94WR6amJJBvn5Q/Mbnzu7OMmD1k+MBeigfBUHhVPcQ/uOb8TsIVj+YfHYfP+ARhsEJlZi8uU6Wkqys0sksNW8aOwO03am96GnRA+XkZljXSZHMNQXVjzB1evkpP1OUDFO0GLutEP6jpMHdgYfCAEnFdowBCoZMGDW3w+pWA2IhCiRtZ3qpcHRBGz6JlOEgBkKN1gQhrKSHyP2jpyMLDLEGSETWJIscQFs9Ej2l2F/2CLxKr0dkOM50uJe/oWP4utOhZ0dnCDCLWXcieICqbPXFBwUCTwHIAPPYxyakdEZe5CpWkdtZsBSuL+/80E2sbOVLFA+VF7WSytZcYcy6VTELsAQztcW9bvmahJM+O2sfSUkbImctk6UBav1AotXt2aAvqm5JZh1T0bnPNX+Eldp2W/ERZueoV3d4thArb6zP+lT+MwAMNWeT1p2zGH6/xJAP/M9r9pUZJZ7jKjG2t4FJdqTQRKHLMhlUcuxzY8= ezaurum@archlinux"
  ];

  # 3. 프린터 서버 설정 (추가됨)
  services.printing = {
    enable = true;
    drivers = with pkgs; [ 
      foomatic-db 
      cups-filters 
      splix
      gutenprint
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

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
  };

  # 4. 필수 패키지
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    coreutils
    usbutils # lsusb — USB 프린터 연결 상태 진단용
  ];


  systemd.services.register-printer = {
  description = "Register Samsung M2020 Printer on boot";
  wantedBy = [ "multi-user.target" ];
  after = [ "cups.service" ];
  serviceConfig = {
    Type = "oneshot";
    # lpadmin은 기존 큐가 있어도 설정을 갱신하므로 매번 실행해 변경 사항을 반영한다.
    # M2020은 splix의 ML-2160 PPD(QPDL v3)로 구동된다 — 공식 ULD는 x86 바이너리 전용이라 aarch64에서 사용 불가.
    # retry-job: 프린터 전원이 꺼져 있어도 큐가 멈추지 않고 재시도한다.
    ExecStart = pkgs.writeShellScript "register-printer" ''
      ${pkgs.cups}/bin/lpadmin -p "Samsung_M2020" \
        -v "usb://Samsung/M2020%20Series?serial=0B2DB8GM5B002WA" \
        -m "samsung/ml2160.ppd" -L "Home-Office" \
        -o printer-error-policy=retry-job -E
    '';
  };
};
}
