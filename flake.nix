{
  description = "OSU Underwater Robotics Team Environment";

  nixConfig = {
    extra-substituters = [
      "https://ros.cachix.org"
      "https://uwrt.cachix.org"
    ];
    extra-trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
      "uwrt.cachix.org-1:<your cache's public key from its Cachix page>"
    ];
  };

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/master";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    riptide-core = {
      url = "github:osu-uwrt/riptide_core/master";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [
                inputs.nix-ros-overlay.overlays.default
                inputs.rust-overlay.overlays.default
                self.overlays.default
              ];
            }
          )
        );
    in
    {
      overlays.default = nixpkgs.lib.composeManyExtensions [
        (import ./overlays/firmware.nix)
        (import ./overlays/ros.nix { inherit (inputs) riptide-core; })
      ];

      lib.forAllSystems = forAllSystems;

      packages = forAllSystems (pkgs: {
        pico-sdk = pkgs.uwrt.pico-sdk;
        libmicroros = pkgs.uwrt.libmicroros;
      });

      devShells = forAllSystems (pkgs: {
        firmware = pkgs.mkShell {
          packages = with pkgs; [
            # C Firmware
            cmake
            ninja
            python3
            gcc-arm-embedded

            # Rust (firmware/nanoros/emulator)
            (rust-bin.stable.latest.default.override { targets = [ "thumbv6m-none-eabi" ]; })
            picotool

            # Flashing/debugging
            probe-rs-tools
            pkg-config

            # Upload tool
            libusb1

            # Utils
            screen
            just
            # The firmware's version stamp (titan_version) runs git; this makes sure it exists in pure
            # environments like CI, where builds would otherwise report None/None
            git
          ];

          CMAKE_POLICY_VERSION_MINIMUM = "3.5";
          PICO_TOOLCHAIN_PATH = "${pkgs.gcc-arm-embedded}";
          PICO_SDK_PATH = "${pkgs.uwrt.pico-sdk}";
          # titan_firmware's lib/micro_ros_pico uses this instead of the Docker-built libmicroros folder
          MICRO_ROS_LIB_DIR = "${pkgs.uwrt.libmicroros}";
        };

        ros = pkgs.mkShell {
          packages = [
            (pkgs.rosPackages.humble.buildEnv {
              paths = with pkgs.rosPackages.humble; [
                ros-core
                pkgs.uwrt.riptide-msgs
              ];
            })
            pkgs.colcon
          ];
        };

        default = self.devShells.${pkgs.stdenv.hostPlatform.system}.firmware;
      });
    };
}
