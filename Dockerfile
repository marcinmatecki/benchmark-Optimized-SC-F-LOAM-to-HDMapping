FROM ubuntu:20.04

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Warsaw

# ---------------------------------------------------------
# Basic dependencies
# ---------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg2 \
    lsb-release \
    software-properties-common \
    build-essential \
    git \
    wget \
    unzip \
    python3-pip \
    python3-dev \
    libceres-dev \
    libeigen3-dev \
    libpcl-dev \
    nlohmann-json3-dev \
    tmux \
    libusb-1.0-0-dev \
    libboost-all-dev \
    libtbb-dev \
    libmetis-dev \
    libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# ROS Noetic
# ---------------------------------------------------------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
    -o /usr/share/keyrings/ros-archive-keyring.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros/ubuntu $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/ros1.list

RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-desktop-full \
    python3-rosdep \
    python3-catkin-tools \
    ros-noetic-geometry-msgs \
    ros-noetic-sensor-msgs \
    ros-noetic-std-msgs \
    ros-noetic-message-generation \
    ros-noetic-message-runtime \
    ros-noetic-catkin \
    ros-noetic-tf \
    ros-noetic-hector-trajectory-server \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# CMake 3.20.5
# ---------------------------------------------------------
WORKDIR /opt

RUN wget https://cmake.org/files/v3.20/cmake-3.20.5.tar.gz \
    && tar -xzf cmake-3.20.5.tar.gz \
    && cd cmake-3.20.5 \
    && ./bootstrap \
    && make -j$(nproc) \
    && make install \
    && cd /opt \
    && rm -rf cmake-3.20.5 cmake-3.20.5.tar.gz

# ---------------------------------------------------------
# GTSAM
#
# IMPORTANT:
# GTSAM 4.0.0-alpha2 must use the system Eigen.
# Otherwise GTSAM may use its bundled Eigen and conflict
# with PCL/Eigen used by the rest of the workspace.
# ---------------------------------------------------------
WORKDIR /opt

RUN wget -O gtsam.zip \
    https://github.com/borglab/gtsam/archive/4.0.0-alpha2.zip \
    && unzip gtsam.zip \
    && cd gtsam-4.0.0-alpha2 \
    && mkdir build \
    && cd build \
    && cmake .. \
        -DGTSAM_USE_SYSTEM_EIGEN=ON \
        -DGTSAM_BUILD_TESTS=OFF \
        -DGTSAM_BUILD_EXAMPLES_ALWAYS=OFF \
        -DGTSAM_BUILD_UNSTABLE=OFF \
    && make -j$(nproc) \
    && make install \
    && cd /opt \
    && rm -rf gtsam.zip gtsam-4.0.0-alpha2

# ---------------------------------------------------------
# Livox SDK
# ---------------------------------------------------------
WORKDIR /opt

RUN git clone https://github.com/Livox-SDK/Livox-SDK.git \
    && cd Livox-SDK \
    && cmake -S . -B build \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build \
    && cd /opt \
    && rm -rf Livox-SDK
# ---------------------------------------------------------
# ROS workspace
# ---------------------------------------------------------
WORKDIR /ros_ws

COPY ./src ./src

COPY patches /tmp/patches
RUN cd /ros_ws/src/Optimized-SC-F-LOAM && \
    patch -p1 < /tmp/patches/optimized-sc-f-loam.patch
# ---------------------------------------------------------
# ROS environment
# ---------------------------------------------------------
RUN echo "source /opt/ros/noetic/setup.bash" >> /etc/bash.bashrc


# ---------------------------------------------------------
# Build
# ---------------------------------------------------------
RUN source /opt/ros/noetic/setup.bash \
    && rm -rf build devel \
    && catkin_make

# ---------------------------------------------------------
# User
# ---------------------------------------------------------
ARG UID=1000
ARG GID=1000

RUN groupadd -g ${GID} ros \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash ros \
    && chown -R ${UID}:${GID} /ros_ws 

    
USER ros


RUN echo "source /opt/ros/noetic/setup.bash" >> /home/ros/.bashrc \
    && echo "source /ros_ws/devel/setup.bash" >> /home/ros/.bashrc

WORKDIR /ros_ws

CMD ["bash"]