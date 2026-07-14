{
  description = "RPI3 Cross-Compilation Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    nixosConfigurations.rpi3-print = nixpkgs.lib.nixosSystem {
      # 빌드 타겟 아키텍처를 명시합니다.
      system = "aarch64-linux"; 
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
