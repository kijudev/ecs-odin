{
  description = "Odin dev shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flecs = {
      url = "github:SanderMertens/flecs/v4.2.0";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, flecs, ... }:
    let
      forAllSystems =
        f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (s: f nixpkgs.legacyPackages.${s});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.odin
            pkgs.ols
            pkgs.lldb
            pkgs.just
            pkgs.clang
            pkgs.python3
            # nixpkgs' samply forgets to link sqlite, drop the override once upstream fixes it.
            (pkgs.samply.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.sqlite ];
            }))
          ];

          ENTT_INCLUDE = "${pkgs.entt}/include";
          FLECS_SRC = "${flecs}";
        };
      });
    };
}
