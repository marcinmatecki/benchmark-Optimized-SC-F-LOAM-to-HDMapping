# Optimized-SC-F-LOAM- to HDMapping simplified instruction

## Step 1 (prepare data)
Download the dataset `kitti_seq05_ros1.bag` by clicking [link](https://huggingface.co/datasets/kubchud/kitti_to_ros/resolve/main/kitti_seq05_ros1.bag) (it is part of [kitti_seq](https://github.com/Jakubach/kitti_to_ros)).

### Extract the dataset

Folder `kitti_seq05_ros1.bag`.

```shell
unzip kitti_seq05_ros1.bag
```
After extraction, the folder name will be `kitti_seq05_ros1.bag`  is an input for further calculations. (without the `.zip` extension).

It should be located in `~/hdmapping-benchmark/data`.  

## Step 2 (prepare docker)
Run following commands in terminal

```shell
mkdir -p ~/hdmapping-benchmark
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-Optimized-SC-F-LOAM-to-HDMapping.git --recursive
cd benchmark-Optimized-SC-F-LOAM-to-HDMapping
git checkout kitti
docker build -t optimized-sc-f-loam_noetic .
```

## Step  3(run docker, file 'kitti_seq05_ros1.bag' should be in '~/hdmapping-benchmark/data')

```shell
cd ~/hdmapping-benchmark/benchmark-Optimized-SC-F-LOAM-to-HDMapping
chmod +x docker_session_run-ros1-optimized-sc-f-loam.sh
cd ~/hdmapping-benchmark/data
~/hdmapping-benchmark/benchmark-Optimized-SC-F-LOAM-to-HDMapping/docker_session_run-ros1-optimized-sc-f-loam.sh kitti_seq05_ros1.bag .
```

## Step 4 (Open and visualize data)
Expected data should appear in ~/hdmapping-benchmark/data/output_hdmapping-optimized-sc-f-loam
Use tool [multi_view_tls_registration_step_2](https://github.com/MapsHD/HDMapping) to open session.json from ~/hdmapping-benchmark/data/output_hdmapping-optimized-sc-f-loam.

You should see following data

lio_initial_poses.reg

poses.reg

scan_lio_*.laz

session.json

trajectory_lio_*.csv

## Contact email
januszbedkowski@gmail.com

## Modifications to Optimized-SC-F-LOAM

This benchmark uses [Optimized-SC-F-LOAM](https://github.com/SlamCabbage/Optimized-SC-F-LOAM)
(upstream commit `<COMMIT>`) with a small set of additions.
**The estimation pipeline (odometry, loop detection, pose graph optimisation) is unchanged**;
the changes only export loop closure data and make the package build and run in Docker.

### What was added

| File | Change |
|---|---|
| `optimized-sc-f-loam/src/laserLoopOptimizationClass.cpp` | Export of every accepted loop closure (CSV + PCD), timestamps on loop cloud messages |
| `optimized-sc-f-loam/include/laserLoopOptimizationClass.h` | Output file stream and output directory members |
| `optimized-sc-f-loam/CMakeLists.txt`, `optimized-sc-f-loam-16/CMakeLists.txt` | Link Boost `serialization` and `thread` (required to build against GTSAM in the Docker image) |
| `optimized-sc-f-loam/launch/optimized_sc_f_loam_mapping.launch` | Bag path set to `/ros_ws/dataset/recorded-optimized-sc-f-loam.bag`; GT trajectory server source frame changed to `base_link` (visualisation only) |

### Loop closure export

For every loop closure that passes verification and is added to the pose graph
(`doloopclosure()`, inside `if (correct)`), the following is written to `/tmp/`
(mounted to `loop_clouds/` on the host by `docker_session_run-ros1-optimized-sc-f-loam.sh`):

**`loop_constraints.csv`** – one row per accepted loop closure:

| Column | Description |
|---|---|
| `current_id` | index of the current keyframe |
| `history_id` | index of the matched historical keyframe |
| `current_time` | timestamp of the current keyframe [s] |
| `history_time` | timestamp of the historical keyframe [s] |
| `tx, ty, tz` | relative translation history → current [m] |
| `roll, pitch, yaw` | relative rotation history → current [rad] |

The relative pose is the same one that is added to the pose graph as
`BetweenFactor(history_id, current_id)`.

**Point clouds (PCD, binary):**

- `loop_<current_id>_current_<history_id>.pcd` – feature points (edge + planar) of the current keyframe,
- `loop_<current_id>_history_<history_id>.pcd` – local feature map around the historical keyframe.

> Note: both clouds contain F-LOAM **feature points**, not raw scans, so they are sparser
> than the original LiDAR data.

**ROS topics:** `/loop_scan_local` and `/loop_submap_local` are now stamped with the
timestamps of the current and historical keyframe, respectively (previously unset),
so the recorded clouds can be matched to the trajectory and the ground truth.

### Notes

- Keyframe indices in `loop_constraints.csv` refer to Optimized-SC-F-LOAM keyframes,
  not to raw LiDAR frame numbers; use `current_time` / `history_time` to match them to the ground truth.
- The output directory `/tmp/` is hard-coded; if the container is run without mounting
  a host folder to `/tmp`, the files are lost when the container exits.
- Files are written synchronously in the loop closure thread. This does not affect the
  estimated trajectory, but adds I/O time to loop closure processing.