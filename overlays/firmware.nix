final: prev: {
  # Force GCC 13 until we upgrade to GCC 15 as it breaks the bootloader
  gcc-arm-embedded = prev.gcc-arm-embedded-13;

  uwrt = (prev.uwrt or { }) // {
    # The SDK is just source: each firmware build compiles its tools (pioasm, elf2uf2) itself.
    # titan_firmware is written for 1.5.1 (nixpkgs' pico-sdk is 2.x); the submodules include tinyusb.
    pico-sdk = prev.fetchFromGitHub {
      owner = "raspberrypi";
      repo = "pico-sdk";
      tag = "1.5.1";
      fetchSubmodules = true;
      hash = "sha256-GY5jjJzaENL3ftuU5KpEZAmEZgyFRtLwGVg3W1e/4Ho=";
    };
  };
}
