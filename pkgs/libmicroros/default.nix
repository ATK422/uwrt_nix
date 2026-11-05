# The micro-ROS static library for the RP2040 boards (titan_firmware's lib/micro_ros_pico/libmicroros), built
# the way micro_ros_setup's generate_lib does it (config/generate_lib/generic/build.sh) instead of in Docker.
#
# * sources.json pins every repository (regenerate it with update-sources.sh); riptide_msgs comes from the
#   flake's riptide-core input, the same revision the ROS shell uses.
# * colcon.meta and toolchain.cmake are copies of titan_firmware's
#   lib/micro_ros_pico/microros_static_library/library_generation files; keep them in sync. The toolchain
#   finds the compilers on PATH instead of through pico-sdk (see its header).
# * Host build tools (ament, colcon, Python with empy 3 for the Humble code generators) come from
#   nix-ros-overlay; everything in the workspace is cross-compiled with the pinned ARM GCC.
{
  lib,
  stdenv,
  runCommand,
  fetchFromGitHub,
  fetchgit,
  cmake,
  colcon,
  gcc-arm-embedded,
  rosPackages,
  riptide-core,
}:
let
  ros = rosPackages.humble;

  fetchSource =
    s:
    if s.type == "github" then
      fetchFromGitHub { inherit (s) owner repo rev hash; }
    else
      fetchgit { inherit (s) url rev hash; };

  sources = lib.mapAttrs (_: fetchSource) (lib.importJSON ./sources.json);

  # The micro-ROS repos and the ROS 2 repos, laid out as create_firmware_ws.sh lays out mcu_ws
  workspaceRepos = lib.filterAttrs (path: _: !lib.hasPrefix "extra/" path) sources;

  # The colcon workspace (mcu_ws), with the extra message packages library_generation.sh adds
  workspace = runCommand "micro-ros-workspace" { } ''
    mkdir -p $out
    ${lib.concatStrings (
      lib.mapAttrsToList (path: src: ''
        mkdir -p $out/${dirOf path}
        cp -r ${src} $out/${path}
      '') workspaceRepos
    )}
    mkdir -p $out/extra_packages
    cp -r ${sources."extra/control_msgs"} $out/extra_packages/control_msgs
    cp -r ${sources."extra/geometry2"}/tf2_msgs $out/ros2/tf2_msgs
    cp -r ${sources."extra/mercury_common"}/mercury_msgs $out/ros2/mercury_msgs
    cp -r ${riptide-core}/riptide_msgs $out/ros2/riptide_msgs
    chmod -R u+w $out

    # Packages micro-ROS leaves out (generate_lib/generic/create.sh). ros2/rcl and ros2/rcpputils, which it
    # also ignores, aren't fetched at all; neither is libyaml_vendor, which only rcl_yaml_param_parser uses.
    touch $out/ros2/rcl_logging/rcl_logging_spdlog/COLCON_IGNORE
    touch $out/ros2/rosidl/rosidl_typesupport_introspection_cpp/COLCON_IGNORE
    touch $out/uros/rcl/rcl_yaml_param_parser/COLCON_IGNORE
    touch $out/uros/rclc/rclc_examples/COLCON_IGNORE
  '';

  python = ros.python3Packages.python.withPackages (
    p: with p; [
      catkin-pkg
      empy
      lark
      numpy
      pyyaml
      setuptools
    ]
  );

  # The record library_generation.sh writes: every repository and the commit it was built from
  builtPackages = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      path: s: "${if s.type == "github" then "https://github.com/${s.owner}/${s.repo}" else s.url} ${s.rev}"
    ) (lib.importJSON ./sources.json)
    ++ [ "https://github.com/osu-uwrt/riptide_core ${riptide-core.rev}" ]
  );
in
stdenv.mkDerivation {
  pname = "libmicroros";
  version = "humble-${builtins.substring 0 8 riptide-core.rev}";

  src = workspace;

  nativeBuildInputs = [
    cmake
    colcon
    python
    gcc-arm-embedded
    ros.ament-cmake
    ros.ament-cmake-ros
    ros.ament-package
    ros.ament-index-python
    ros.osrf-pycommon
  ];

  # colcon runs CMake for every package; the workspace root has no CMakeLists.txt
  dontUseCmakeConfigure = true;

  buildPhase = ''
    runHook preBuild
    export HOME=$TMPDIR
    colcon build \
      --merge-install \
      --packages-ignore-regex='.*_cpp' \
      --metas ${./colcon.meta} \
      --event-handlers console_cohesion+ \
      --cmake-args \
        --no-warn-unused-cli \
        -DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=OFF \
        -DTHIRDPARTY=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE=${./toolchain.cmake}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out merge
    ws=$PWD

    # One archive from every package's archive, object files prefixed with their library's name
    cd merge
    for file in $(find $ws/install/lib -name '*.a'); do
      folder=$(basename "$file" .a)
      mkdir "$folder"
      (cd "$folder" && arm-none-eabi-ar x "$file" && for f in *; do mv "$f" "../$folder-$f"; done)
      rmdir "$folder"
    done
    arm-none-eabi-ar rc $out/libmicroros.a *.o *.obj 2>/dev/null || arm-none-eabi-ar rc $out/libmicroros.a *.o
    arm-none-eabi-ranlib $out/libmicroros.a
    cd $ws

    # Headers only, with include/<pkg>/<pkg>/... flattened to include/<pkg>/... as library_generation.sh does
    cp -R install/include $out/include
    find $out/include -type f -not -name '*.h' -not -name '*.hpp' -delete
    find $out/include -type d -empty -delete
    for pkg in $(colcon list --names-only); do
      if [ -d "$out/include/$pkg/$pkg" ]; then
        cp -r "$out/include/$pkg/$pkg/." "$out/include/$pkg/"
        rm -rf "$out/include/$pkg/$pkg"
      fi
    done

    # The message, service and action types the library supports
    find ros2 extra_packages \( -name '*.msg' -o -name '*.srv' -o -name '*.action' \) \
      | awk -F/ '{print $(NF-2)"/"$NF}' | sort > $out/available_ros2_types
    cat > $out/built_packages <<'EOF'
    ${builtPackages}
    EOF
    sort -o $out/built_packages $out/built_packages
    runHook postInstall
  '';

  meta = {
    description = "micro-ROS (Humble) static library for UWRT's RP2040 boards, with the riptide messages";
    platforms = lib.platforms.unix;
  };
}
