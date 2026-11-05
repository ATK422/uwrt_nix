{
  riptide-core,
  chameleon-tf,
  nortek-dvl,
}:
final: prev:
let
  ros = final.rosPackages.humble;
  buildMessagePkg =
    {
      name,
      src,
      deps ? [ ],
      folder ? name,
    }:
    ros.buildRosPackage {
      inherit src;
      pname = "ros-humble-${name}";
      version = "0-unstable-${builtins.substring 0 8 src.rev}";
      sourceRoot = "source/${builtins.replaceStrings [ "-" ] [ "_" ] folder}";
      buildType = "ament_cmake";
      nativeBuildInputs = [
        ros.ament-cmake
        ros.rosidl-default-generators
      ];
      propagatedBuildInputs =
        with ros;
        [
          rosidl-default-runtime
          geometry-msgs
        ]
        ++ deps;
      cmakeFlags = [ "-DBUILD_TESTING=OFF" ];
    };
in
{
  uwrt = (prev.uwrt or { }) // {
    riptide-msgs = buildMessagePkg {
      name = "riptide-msgs2";
      src = riptide-core;
      deps = with ros; [
        action-msgs
        std-msgs
        sensor-msgs
      ];
      folder = "riptide_msgs";
    };

    chameleon-tf-msgs = buildMessagePkg {
      name = "chameleon-tf-msgs";
      src = chameleon-tf;
      deps = with ros; [
        action-msgs
      ];
    };

    nortek-dvl-msgs = buildMessagePkg {
      name = "nortek-dvl-msgs";
      src = nortek-dvl;
    };

    libmicroros = final.callPackage ../pkgs/libmicroros { inherit riptide-core; };
  };
}
