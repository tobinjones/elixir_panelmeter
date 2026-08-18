{
  description = "ADMX3652 panelmeter using elixir and nerves";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      # OTP 29 is not the nixpkgs default (that is still 28.x), so pull the
      # whole BEAM package set built against erlang_29 and take Elixir from it.
      beam = pkgs.beam.packages.erlang_29;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          beam.erlang # 29.0.5
          beam.elixir_1_20 # 1.20.3

          # Nerves host-side tooling: fwup assembles/burns .fw images,
          # squashfs-tools builds the rootfs.
          pkgs.fwup
          pkgs.squashfsTools

          # Fetching hex packages and the Nerves toolchain/system tarballs.
          pkgs.curl
          pkgs.git
          pkgs.xz
          pkgs.unzip
        ];

        # Nerves cross-compiles for this target rather than the host.
        MIX_TARGET = "rpi3";

        # Nerves downloads prebuilt toolchains and host tools that are linked
        # against a normal FHS layout; programs.nix-ld in the system config
        # supplies the loader they expect.
        shellHook = ''
          echo "erlang $(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().')  elixir $(elixir --version | sed -n 's/^Elixir \([0-9.]*\).*/\1/p')  MIX_TARGET=$MIX_TARGET"
        '';
      };
    };
}
