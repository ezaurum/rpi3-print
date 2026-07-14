{
  description = "RPI3 Cross-Compilation Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # 삼성 ULD(rastertospl)는 x86_64 바이너리 전용이다.
      # x86_64용 패키지를 그대로 클로저에 넣고, Pi에서는 qemu binfmt 에뮬레이션으로 실행한다.
      # (M2020은 splix QPDL을 받으면 펌웨어가 크래시해서 ULD가 유일한 선택지 — README 참고)
      pkgsX86 = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true; # ULD는 unfree 라이선스
      };
    in
    {
      nixosConfigurations.rpi3-print = nixpkgs.lib.nixosSystem {
        # 빌드 타겟 아키텍처를 명시합니다.
        system = "aarch64-linux";
        specialArgs = { inherit pkgsX86; };
        modules = [
          ./configuration.nix
          ({ pkgs, ... }: {
            # 교차 컴파일 설정
            nixpkgs.hostPlatform = "aarch64-linux";
          })
        ];
      };
    };
}
