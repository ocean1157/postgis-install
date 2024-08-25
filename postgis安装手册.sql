 
 yum install -y gcc gmp-devel  mpfr-devel  boost-devel libxml2 libxml2-devel

## 安装cmake 
tar -zxvf CMake-3.30.2.tar.gz 
cd CMake-3.30.2/
./bootstrap
gmake
make install

 

##geos 安装
cd ..
tar xvfj geos-3.9.5.tar.bz2 
cd geos-3.9.5
mkdir _build
cd _build
cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    ..
make
make install
  
 
 ## sqlite3 
 cd ../..
tar zxvf sqlite-autoconf-3460100.tar.gz
cd sqlite-autoconf-3460100/
./configure --prefix=/usr/local/sqlite
make
make install

 
/**********键入临时变量**********/
export SQLITE3=/usr/local/sqlite
export PATH=$SQLITE3/bin:$PATH
export PKG_CONFIG_PATH=/usr/local/sqlite/lib/pkgconfig
 



## proj 安装
cd ..
tar -zxvf proj-6.3.1.tar.gz
cd proj-6.3.1
export SQLITE3=/usr/local/sqlite
export PATH=$SQLITE3/bin:$PATH
export PKG_CONFIG_PATH=/usr/local/sqlite/lib/pkgconfig
./configure
make
make install
 
 
 
## protobuf 安装
cd .. 
tar -zxvf protobuf-all-3.15.3.tar.gz
cd protobuf-3.15.3
./configure
make
make install

export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

 
## 安装protobuf-c
cd ..
 tar -zxvf protobuf-c-1.3.3.tar.gz
cd protobuf-c-1.3.3
./configure
make
make install


## 安装gdal
cd ..
 tar -zxvf gdal-3.0.4.tar.gz 
 cd  gdal-3.0.4
./configure LDFLAGS="-L/usr/local/lib" CPPFLAGS="-I/usr/local/include"
make
make install



## 安装CGAL
cd .. 
tar -xvf CGAL-4.14.3.tar.xz
cd CGAL-4.14.3
mkdir build && cd build
cmake ..
make
make install

   
## 安装SFCGAL
cd ../..
tar -zxvf v1.3.7 
cd SFCGAL-1.3.7/
mkdir build && cd build
cmake .. 
make
make install

ln -s /usr/local/lib64/libSFCGAL.so /usr/local/lib/libSFCGAL.so
ln -s /usr/local/lib64/libSFCGAL.so.1 /usr/local/lib/libSFCGAL.so.1
 



## 安装pcre
cd ../..
tar -zxvf pcre-8.45.tar.gz 
cd pcre-8.45
./configure 
make
make install



## 安装postgis
export PG_CONFIG=/home/postgres/pg/bin/pg_config
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
tar -zxvf postgis-3.4.2.tar.gz 
cd postgis-3.4.2/ 
./configure --without-raster
make 
make install 

echo "/usr/local/lib" | sudo tee -a /etc/ld.so.conf
echo "/usr/local/lib64" | sudo tee -a /etc/ld.so.conf
sudo ldconfig
chown -R postgres:postgres /home/postgres/pg/lib 


 
重启数据库
pg_ctl restart 
create extension postgis ;
 
 
 
 
 
 
 
