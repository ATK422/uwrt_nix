{ riptide-core }:
final: prev:
let
  ros = final.rosPackages.humble;
in
{
  uwrt = (prev.uwrt or { }) // {
    riptide-msgs = ros.buildRosPackage {
      pname = "ros-humble-riptide-msgs2";
      version = "0-unstable-${builtins.substring 0 8 riptide-core.rev}";
      src = riptide-core;
      sourceRoot = "source/riptide_msgs";
      buildType = "ament_cmake";
      nativeBuildInputs = [
        ros.ament-cmake
        ros.rosidl-default-generators
      ];
      propagatedBuildInputs = with ros; [
        action-msgs
        geometry-msgs
        std-msgs
        sensor-msgs
        rosidl-default-runtime
      ];
      cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
    };

    # The micro-ROS library for the C firmware, with the same riptide_msgs revision as above
    libmicroros = final.callPackage ../pkgs/libmicroros { inherit riptide-core; };
  };
}
