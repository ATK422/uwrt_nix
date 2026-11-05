# uwrt_nix

The development environment for UWRT's firmware and robot software, as a Nix flake. It pins the ARM compiler,
the Pico SDK, Rust, ROS 2 Humble, the riptide messages and the micro-ROS library, so every machine builds with
the same versions. Repositories such as `titan_firmware`, `firmware_simulator` and `nano_ros` use it through a
small `flake.nix` of their own.

## Setup

1. Install Nix.
   - Linux / Windows (WSL2): `curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh -s -- --daemon`
   - macOS: `curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install | sh`

   If the installer asks whether to enable flakes, say yes. Open a new terminal afterwards so `nix` is on your
   PATH.

2. Turn on flakes and let the flake's binary caches be used. The Nix daemon only uses caches named by a flake
   when your user is trusted, so this goes in the system config:

   ```sh
   echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
   echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
   echo "accept-flake-config = true" | sudo tee -a /etc/nix/nix.conf
   ```

   Then restart the daemon:
   - Linux / WSL2: `sudo systemctl restart nix-daemon`
   - macOS: `sudo launchctl kickstart -k system/org.nixos.nix-daemon`

   Without the caches everything still works, but your first shell compiles for an hour or more instead of
   downloading.

3. Install direnv, which loads a repository's environment when you `cd` into it:

   ```sh
   nix profile add nixpkgs#direnv nixpkgs#nix-direnv
   mkdir -p ~/.config/direnv
   echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' > ~/.config/direnv/direnvrc
   ```

   Then hook it into your shell and open a new terminal:

   | Shell | Add this line | To |
   |---|---|---|
   | bash | `eval "$(direnv hook bash)"` | `~/.bashrc` |
   | zsh | `eval "$(direnv hook zsh)"` | `~/.zshrc` |
   | fish | `direnv hook fish \| source` | `~/.config/fish/config.fish` |

4. Clone a repository and enter it:

   ```sh
   git clone git@github.com:osu-uwrt/titan_firmware.git
   cd titan_firmware
   direnv allow
   ```

   The first time takes a few minutes while Nix downloads the tools. After that, entering the directory is
   instant, and leaving it unloads everything. If a repository has a `flake.nix` but no `.envrc`, create one
   with `echo "use flake" > .envrc`.

You don't need direnv: `nix develop` in a repository gives you the same shell for one session.

## What you get

| Shell | Contents |
|---|---|
| `firmware` (the default) | ARM GCC 13, CMake, Ninja, the Pico SDK 1.5.1, the micro-ROS library, Rust with the `thumbv6m-none-eabi` target, picotool, probe-rs, just, git |
| `ros` | ROS 2 Humble (`ros-core`), the riptide messages, colcon |

The firmware shell also sets the variables `titan_firmware`'s build reads:

| Variable | Points at |
|---|---|
| `PICO_SDK_PATH` | the pinned Pico SDK, instead of the `lib/pico-sdk` submodule |
| `MICRO_ROS_LIB_DIR` | the micro-ROS library built by this flake, instead of `lib/micro_ros_pico/libmicroros` |
| `PICO_TOOLCHAIN_PATH` | the pinned ARM GCC |

Without these variables (no Nix), `titan_firmware` falls back to the submodule and the Docker-built library as
before.

The SDK and the library can also be built on their own: `nix build .#pico-sdk`, `nix build .#libmicroros`.

## Platforms

- **Linux:** everything works. For flashing over USB, copy `titan_firmware/tools/rp2040.rules` to
  `/etc/udev/rules.d/`.
- **NixOS:** skip steps 1 to 3. Set `nix.settings` (`experimental-features`, `trusted-users`) and
  `programs.direnv.enable = true` in your configuration instead. For the USB rules, put the contents of
  `rp2040.rules` in `services.udev.extraRules`, with `TAG+="uaccess"` in place of `GROUP="plugdev"` (NixOS has
  no plugdev group).
- **macOS:** building firmware, flashing over USB, debugging and the simulator all work. CAN doesn't: the team's
  tools use Linux SocketCAN, so do CAN work on the robot computer over SSH. ROS 2 builds, but running it on
  macOS hasn't been tested much yet.
- **Windows:** use WSL2 on Windows 11.
  - Keep repositories inside WSL (`~/...`), not under `/mnt/c`; builds there are far slower.
  - USB devices need [usbipd-win](https://github.com/dorssel/usbipd-win): `usbipd list`, then once per device
    `usbipd bind --busid <id>` (as administrator), then `usbipd attach --wsl --busid <id> --auto-attach`.
    `--auto-attach` keeps reattaching when a board reboots into BOOTSEL.
  - For ROS to reach the robot, set `networkingMode=mirrored` under `[wsl2]` in `%UserProfile%\.wslconfig`.
  - WSL's kernel has no CAN drivers; do CAN work on the robot computer.
  - GUI programs from the `ros` shell may not find the GPU under WSL. This isn't handled yet.

The simulator's virtual CAN buses (`firmware_simulator/scripts/vcan_up.sh`) need the Linux `vcan` module, so
they work on Linux and NixOS only.

## Using it in a repository

A repository that only needs the shells as they are:

```nix
{
  inputs.uwrt.url = "github:atk422/uwrt_nix";
  outputs = { uwrt, ... }: {
    devShells = uwrt.devShells;
  };
}
```

A repository that combines shells or adds its own tools:

```nix
{
  inputs.uwrt.url = "github:atk422/uwrt_nix";
  outputs = { uwrt, ... }: {
    devShells = uwrt.lib.forAllSystems (pkgs:
      let
        system = pkgs.stdenv.hostPlatform.system;
      in
      {
        default = pkgs.mkShell {
          inputsFrom = [ uwrt.devShells.${system}.firmware uwrt.devShells.${system}.ros ];
          packages = [ pkgs.can-utils ];
          # inputsFrom brings the other shells' packages but not their variables
          inherit (uwrt.devShells.${system}.firmware)
            PICO_SDK_PATH PICO_TOOLCHAIN_PATH CMAKE_POLICY_VERSION_MINIMUM MICRO_ROS_LIB_DIR;
        };
      });
  };
}
```

`uwrt.lib.forAllSystems` gives you `pkgs` with this flake's overlays applied, so `pkgs.uwrt.pico-sdk`,
`pkgs.uwrt.libmicroros`, `pkgs.uwrt.riptide-msgs` and the pinned compiler are all available. Commit the
repository's `flake.lock` too; it records which version of uwrt_nix the repository uses.

To pick up changes made here, run `nix flake update uwrt` in the repository and commit the new `flake.lock`.

## When something goes wrong

- **`path '.../flake.nix' does not exist`, or Nix doesn't see a file you just created:** flakes only see files
  git knows about. `git add` the file (committing isn't necessary).
- **The first shell compiles for a long time:** the caches aren't being used. Look for
  `ignoring untrusted substituter` in the output and redo step 2.
- **`direnv: error .envrc is blocked`:** run `direnv allow`. You need to do this again whenever `.envrc` changes.
- **The shell didn't change after a `flake.nix` or `flake.lock` change:** run `direnv reload`.
- **A board still builds with the old compiler or SDK:** CMake remembers both in the build folder. Delete the
  board's `build/` folder and build again.
- **The firmware reports its version as `None/None`:** it was built outside the repository. Build in the board's
  own `build/` folder; the version comes from git there.
- **`HTTP error 404` fetching `github:atk422/uwrt_nix`:** the repository is private and Nix has no GitHub
  credentials. Add `access-tokens = github.com=<a token with read access>` to `~/.config/nix/nix.conf`
  (`gh auth token` prints yours).

## Maintaining

- **Updating everything:** `nix flake update`, check that both shells still build, push. CI refills the cache.
- **The riptide messages:** `nix flake update riptide-core`. This updates the ROS shell and the micro-ROS
  library together, so the robot and the firmware always use the same message definitions.
- **micro-ROS:** every source repository and commit is listed in `pkgs/libmicroros/update-sources.sh`. Change
  a commit, run the script, and commit the regenerated `sources.json`. `colcon.meta` (the firmware's publisher,
  subscriber and service limits) and `toolchain.cmake` are copies of `titan_firmware`'s files in
  `lib/micro_ros_pico/microros_static_library/library_generation/`; keep them in sync.
- **The ARM compiler:** pinned to GCC 13 in `overlays/firmware.nix`. GCC 15 breaks the Titan bootloader link and
  makes the SmartBattery bootloader too large for its flash region.
- **The Pico SDK:** pinned to 1.5.1 in `overlays/firmware.nix`, the version `titan_firmware` is written for.
- **The binary cache:** CI (`.github/workflows/cache.yml`) builds both shells on x86 Linux, ARM Linux and macOS
  on every push to master and uploads the results to the `uwrt` Cachix cache. It needs the
  `CACHIX_AUTH_TOKEN` repository secret.
