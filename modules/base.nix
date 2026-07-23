{ pkgs, ... }:

# 이 기기가 어떤 역할을 맡든 공통으로 필요한 시스템 기반 설정.
# (부팅, 루트 파일시스템, 네트워크 신원, SSH, Tailscale, 공통 CLI 도구)
# 프린터·음성 등 개별 역할은 modules/ 아래 별도 파일로 분리한다.

{
  # 1. 시스템 핵심 설정
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # 내장 WiFi용 Broadcom 펌웨어. 없으면 wlan0 인터페이스 자체가 안 잡힌다.
  # 실제 보드는 Pi 3 B+ (BCM4345/6 → brcmfmac43455, dmesg 실측).
  # (linux-firmware 전체 대신 RPi 전용 패키지만 넣어 클로저 크기를 줄임)
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

  networking.hostName = "rpi3-print";
  networking.networkmanager.enable = true;
  system.stateVersion = "25.05";

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

  # 역할과 무관하게 쓰는 공통 CLI 도구
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    coreutils
  ];
}
