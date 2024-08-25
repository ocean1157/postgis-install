#!/bin/bash

# 使用命令行参数设置变量
while getopts "i:s:p:c:" opt; do
  case ${opt} in
    i )
      INSTALL_DIR=$OPTARG
      ;;
    s )
      SQLITE_DIR=$OPTARG
      ;;
    p )
      PG_BIN_DIR=$OPTARG
      ;;
    c )
      PKG_CONFIG_PATH=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-i geos的安装路径] [-s SQLITE3安装路径] [-p PG的bin路劲] [-c $SQLITE3/lib/pkgconfig的路径]"
      exit 1
      ;;
  esac
done
shift $((OPTIND -1))

# 如果没有提供路径，则使用默认值
INSTALL_DIR="${INSTALL_DIR:-/usr/local}"
SQLITE_DIR="${SQLITE_DIR:-$INSTALL_DIR/sqlite}"
PG_BIN_DIR="${PG_BIN_DIR:-/home/postgres/pg/bin}"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-$INSTALL_DIR/lib/pkgconfig}"

# 显示进度条的函数
progress_bar() {
    local progress=(${1})
    local total_steps=(${2})
    local bar_length=50
    local percent=$((100 * progress / total_steps))
    local filled_length=$((bar_length * progress / total_steps))
    local bar=$(printf "%-${bar_length}s" "#" | cut -c1-${filled_length})
    printf "\r[%-${bar_length}s] %d%%" "${bar}" "${percent}"
}

# 帮助函数，用于运行命令并更新进度
run_command() {
    ((current_step++))
    echo
    echo "步骤 $current_step/$total_steps: $1"
    progress_bar ${current_step} ${total_steps}
    eval $2
    if [ $? -ne 0 ]; then
        echo -e "\n执行 $1 时出错，正在退出..."
        exit 1
    fi
    echo
}

# 初始化
total_steps=12
current_step=0

# 1. 安装依赖
run_command "安装依赖项" "yum install -y gcc gmp-devel mpfr-devel boost-devel libxml2 libxml2-devel"

# 2. 安装 CMake
run_command "安装 CMake" "tar -zxvf CMake-3.30.2.tar.gz && cd CMake-3.30.2/ && ./bootstrap && gmake && make install && cd .."

# 3. 安装 GEOS
run_command "安装 GEOS" "tar xvfj geos-3.9.5.tar.bz2 && cd geos-3.9.5 && mkdir _build && cd _build && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR .. && make && make install && cd ../.."

# 4. 安装 SQLite3
run_command "安装 SQLite3" "tar zxvf sqlite-autoconf-3460100.tar.gz && cd sqlite-autoconf-3460100/ && ./configure --prefix=$SQLITE_DIR && make && make install && cd .."

# 5. 安装 Proj
run_command "安装 Proj" "export SQLITE3=$SQLITE_DIR && export PATH=\$SQLITE3/bin:\$PATH && export PKG_CONFIG_PATH=\$SQLITE3/lib/pkgconfig && tar -zxvf proj-6.3.1.tar.gz && cd proj-6.3.1 && ./configure && make && make install && cd .."

# 6. 安装 Protobuf
run_command "安装 Protobuf" "tar -zxvf protobuf-all-3.15.3.tar.gz && cd protobuf-3.15.3 && ./configure && make && make install && export LD_LIBRARY_PATH=$INSTALL_DIR/lib:\$LD_LIBRARY_PATH && export PKG_CONFIG_PATH=\$INSTALL_DIR/lib/pkgconfig && cd .."

# 7. 安装 Protobuf-C
run_command "安装 Protobuf-C" "tar -zxvf protobuf-c-1.3.3.tar.gz && cd protobuf-c-1.3.3 && ./configure && make && make install && cd .."

# 8. 安装 GDAL
run_command "安装 GDAL" "tar -zxvf gdal-3.0.4.tar.gz && cd gdal-3.0.4 && ./configure LDFLAGS=\"-L$INSTALL_DIR/lib\" CPPFLAGS=\"-I$INSTALL_DIR/include\" && make && make install && cd .."

# 9. 安装 CGAL
run_command "安装 CGAL" "tar -xvf CGAL-4.14.3.tar.xz && cd CGAL-4.14.3 && mkdir build && cd build && cmake .. && make && make install && cd ../.."

# 10. 安装 SFCGAL
run_command "安装 SFCGAL" "tar -zxvf v1.3.7 && cd SFCGAL-1.3.7/ && mkdir build && cd build && cmake .. && make && make install && ln -s $INSTALL_DIR/lib64/libSFCGAL.so $INSTALL_DIR/lib/libSFCGAL.so && ln -s $INSTALL_DIR/lib64/libSFCGAL.so.1 $INSTALL_DIR/lib/libSFCGAL.so.1 && cd ../.."

# 11. 安装 PCRE
run_command "安装 PCRE" "tar -zxvf pcre-8.45.tar.gz && cd pcre-8.45 && ./configure && make && make install && cd .."

# 12. 安装 PostGIS
run_command "安装 PostGIS" "export PG_CONFIG=$PG_BIN_DIR/pg_config && export PKG_CONFIG_PATH=$PKG_CONFIG_PATH && tar -zxvf postgis-3.4.2.tar.gz && cd postgis-3.4.2/ && ./configure --without-raster && make && make install && cd .."

echo -e "\n安装完成。"
