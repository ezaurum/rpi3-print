{ ... }:

# 이 파일은 임포트 목록만 담는다. 실제 설정은 역할별로 modules/ 아래에 있다.
# 역할을 빼려면 해당 줄을 지우고, 새 역할(서브넷 라우터·음성 새틀라이트 등)은
# modules/ 아래 파일을 추가한 뒤 여기에 한 줄 더한다.
{
  imports = [
    ./modules/base.nix
    ./modules/print-server.nix
  ];
}
