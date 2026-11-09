#!/bin/bash

IMAGE_NAME='optimized-sc-f-loam_noetic'
TMUX_SESSION='ros1_session'

DATASET_CONTAINER_PATH='/ros_ws/dataset/recorded-optimized-sc-f-loam.bag'
BAG_OUTPUT_CONTAINER='/ros_ws/recordings'

RECORDED_BAG_NAME="recorded-optimized-sc-f-loam.bag"
HDMAPPING_OUT_NAME="output_hdmapping"

usage() {
  echo "Usage:"
  echo "  $0 <input.bag> <output_dir>"
  echo
  echo "If no arguments are provided, a GUI file selector will be used."
  exit 1
}

echo "=== optimized-sc-f-loam rosbag pipeline ==="

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

if [[ $# -eq 2 ]]; then
  DATASET_HOST_PATH="$1"
  BAG_OUTPUT_HOST="$2"
elif [[ $# -eq 0 ]]; then
  command -v zenity >/dev/null || {
    echo "Error: zenity is not available"
    exit 1
  }
  DATASET_HOST_PATH=$(zenity --file-selection --title="Select BAG file")
  BAG_OUTPUT_HOST=$(zenity --file-selection --directory --title="Select output directory")
else
  usage
fi

if [[ -z "$DATASET_HOST_PATH" || -z "$BAG_OUTPUT_HOST" ]]; then
  echo "Error: no file or directory selected"
  exit 1
fi

if [[ ! -f "$DATASET_HOST_PATH" ]]; then
  echo "Error: BAG file does not exist: $DATASET_HOST_PATH"
  exit 1
fi

mkdir -p "$BAG_OUTPUT_HOST"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

WORK_DIR="$SCRIPT_DIR"


LOOP_CLOUDS_DIR="$WORK_DIR/loop_clouds"
MESSAGE_DIR="$WORK_DIR/message"
SCANS_DIR="$WORK_DIR/message/Scans"

mkdir -p "$LOOP_CLOUDS_DIR" "$MESSAGE_DIR" "$SCANS_DIR"

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
BAG_OUTPUT_HOST=$(realpath "$BAG_OUTPUT_HOST")

echo "Input bag : $DATASET_HOST_PATH"
echo "Output dir: $BAG_OUTPUT_HOST"

xhost +local:docker

docker run -it --rm \
  --network host \
  -e DISPLAY=$DISPLAY \
  -e ROS_HOME=/tmp/.ros \
  -u "$(id -u):$(id -g)" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$DATASET_HOST_PATH":"$DATASET_CONTAINER_PATH":ro \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  -v "$LOOP_CLOUDS_DIR":/tmp \
  -v "$MESSAGE_DIR":/home/llz/message/ \
  "$IMAGE_NAME" \
  /bin/bash -c '
    tmux new-session -d -s '"$TMUX_SESSION"'

    # ---------- PANEL 1: ROS launch ----------
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 5
source /opt/ros/noetic/setup.bash
source /ros_ws/devel/setup.bash
roslaunch optimized_sc_f_loam optimized_sc_f_loam_mapping.launch

'\'' C-m

    # ---------- PANEL 2: rosbag record ----------
    tmux split-window -v -t '"$TMUX_SESSION"'
    tmux send-keys -t '"$TMUX_SESSION"' '\''sleep 2
source /opt/ros/noetic/setup.bash
source /ros_ws/devel/setup.bash
echo "[record] start"
rosbag record /velodyne_points_filtered /odom /aft_pgo_odom /loop_scan_local /loop_submap_local -O '"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME"'
echo "[record] exit"
'\'' C-m

# ---------- PANEL 4: controller ----------
tmux new-window -t '"$TMUX_SESSION"' -n control '\''
source /opt/ros/noetic/setup.bash
source /ros_ws/devel/setup.bash

echo "[control] waiting for rosbag play..."

# Czekamy aż rosbag play wystartuje
while ! pgrep -f "/opt/ros/noetic/lib/rosbag/play" >/dev/null; do
    sleep 5
done

echo "[control] rosbag play detected!"
echo "[control] waiting for rosbag play to finish..."

# Czekamy na komunikat roslaunch:
# [rosbag_play-2] process has finished cleanly
while true; do
    if tmux capture-pane -t '"$TMUX_SESSION"'.0 -p -S -1000 | grep -q "\[rosbag_play-2\] process has finished cleanly"; then
        break
    fi

    sleep 2
done

echo "[control] rosbag play finished!"

sleep 2

echo "[control] stopping recorder..."
tmux send-keys -t '"$TMUX_SESSION"'.1 C-c

sleep 2

echo "[control] killing roslaunch..."
pkill -SIGINT -f "roslaunch optimized_sc_f_loam"

echo "[control] done"

sleep 10

pkill tmux -f
pkill ros -f

'\''

    tmux attach -t '"$TMUX_SESSION"'
  '

docker run -it --rm \
  --network host \
  -e DISPLAY="$DISPLAY" \
  -e ROS_HOME=/tmp/.ros \
  -u 1000:1000 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e
    source /opt/ros/noetic/setup.bash
    source /ros_ws/devel/setup.bash
    rosrun optimized-sc-f-loam-to-hdmapping listener \
      \"$BAG_OUTPUT_CONTAINER/$RECORDED_BAG_NAME\" \
      \"$BAG_OUTPUT_CONTAINER/$HDMAPPING_OUT_NAME-optimized-sc-f-loam\"
  "

echo "=== DONE ==="