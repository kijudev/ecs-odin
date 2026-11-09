{
  description = "Odin dev shell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # flecs isn't in nixpkgs; its single-file distribution is compiled straight from the repo.
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
          ];

          # Used by bench/justfile to build the EnTT and flecs comparison benchmarks.
          ENTT_INCLUDE = "${pkgs.entt}/include";
          FLECS_SRC = "${flecs}";
        };
      });
    };
}
