#!/usr/bin/env bash
# Writes sources.json: every repository the micro-ROS library is built from, with its pinned commit and
# Nix hash. Edit a commit below and rerun this script to update a pin.
#
# The commits are the ones titan_firmware's Docker build recorded in lib/micro_ros_pico/built_packages,
# except mercury_common and geometry2, which that build cloned unpinned. riptide_core is not listed:
# it comes from the flake's riptide-core input, so firmware and robot messages always match.
#
# Each line: <path in the colcon workspace> <github:owner/repo or a git+https URL> <commit>
set -euo pipefail
cd "$(dirname "$0")"

repos="
eProsima/Micro-CDR                  github:eProsima/Micro-CDR                     ed4fd513a24a53b93d548d342cb7aa0a18716f04
eProsima/Micro-XRCE-DDS-Client      github:eProsima/Micro-XRCE-DDS-Client         83f129a80770a09aac9e823896ecbf6a0eddf0fc
uros/rcl                            github:micro-ROS/rcl                          aa45efa10cdcc8b8adfb61dd008543466e25ebf0
uros/rclc                           github:ros2/rclc                              10eadcc6444a3af3b21e7fb80a626f8c391450e0
uros/micro_ros_utilities            github:micro-ROS/micro_ros_utilities          74fbd3ed2e451e50aea49e45d143905e496c8f10
uros/rcutils                        github:micro-ROS/rcutils                      aac2dcd1f7b3e767e4941c7bab96d303b7c9b404
uros/micro_ros_msgs                 github:micro-ROS/micro_ros_msgs               c9062eb3860d16c1bff1423923de3b0956fd4734
uros/rmw_microxrcedds               github:micro-ROS/rmw-microxrcedds             b5ad1740ecfc611496a6ba2f12c7540b85cbec8f
uros/rosidl_typesupport             github:micro-ROS/rosidl_typesupport           520d9243f17e0cfe53c658b8051ebe2f89ad7c68
uros/rosidl_typesupport_microxrcedds github:micro-ROS/rosidl_typesupport_microxrcedds 68b96291bca436243c9f3f9b054e5e117e58f8f7
uros/tracetools                     git+https://gitlab.com/micro-ROS/ros_tracing/ros2_tracing.git 548634dd2837d65c043436c8186614e924be5c6c
ros2/rmw                            github:ros2/rmw                               566d17a97e87bc5336ce33fb025ce8e952a3326a
ros2/rosidl_defaults                github:ros2/rosidl_defaults                   8266f1c0f062d405595570209cfb0ed3f71684ae
ros2/rosidl                         github:ros2/rosidl                            02a3de88b75af9c8d4efe167db4b14504e81cb90
ros2/rosidl_dds                     github:ros2/rosidl_dds                        ab8497770c652edb40d6b1591118198cbcf14237
ros2/rmw_implementation             github:ros2/rmw_implementation                a0f867e8787cc522300e6971013c423ca59c0059
ros2/common_interfaces              github:ros2/common_interfaces                 08434490d3e4abd37ccc5462cdde69b88853b5b8
ros2/rcl_interfaces                 github:ros2/rcl_interfaces                    82776fc9068d1e0cd4af11c2e2700195994b2eb1
ros2/unique_identifier_msgs         github:ros2/unique_identifier_msgs            27767cefcf8a80da44641dc208c57722c28aa11c
ros2/rcl_logging                    github:ros2/rcl_logging                       5bab8cf7a19c466de77aee35fa55778298563c57
ros2/test_interface_files           github:ros2/test_interface_files              a0c8f5e338490ddf8b98238dce35c06810115e8b
ros2/example_interfaces             github:ros2/example_interfaces                f8deb566a1facf91bd38b9f00c4cf684c5007d85
extra/control_msgs                  github:ros-controls/control_msgs              1416954c31432c192ff95a06559847e87386cf60
extra/geometry2                     github:ros2/geometry2                         404b7224d623d614f18fa9738dbf1716403d857e
extra/mercury_common                github:osu-uwrt/mercury_common                4e9244e35bf9f14512d460b408b60fbfc0913c05
"

{
  echo "{"
  first=1
  while read -r path ref rev; do
    [ -z "$path" ] && continue
    case $ref in
      github:*) json=$(nix flake prefetch --json "$ref/$rev") ;;
      # GitLab's API can't fetch repos in nested groups, so those are fetched as plain git (fetchgit)
      git+*) json=$(nix flake prefetch --json "$ref?rev=$rev") ;;
      *) echo "unknown source $ref" >&2; exit 1 ;;
    esac
    hash=$(python3 -c 'import sys, json; print(json.loads(sys.argv[1])["hash"])' "$json")
    [ $first = 1 ] || echo ","
    first=0
    case $ref in
      github:*)
        repo=${ref#github:}
        printf '  "%s": { "type": "github", "owner": "%s", "repo": "%s", "rev": "%s", "hash": "%s" }' \
          "$path" "${repo%/*}" "${repo#*/}" "$rev" "$hash" ;;
      git+*)
        printf '  "%s": { "type": "git", "url": "%s", "rev": "%s", "hash": "%s" }' "$path" "${ref#git+}" "$rev" "$hash" ;;
    esac
    echo "$path" >&2
  done <<< "$repos"
  echo
  echo "}"
} > sources.json
echo "wrote sources.json" >&2
