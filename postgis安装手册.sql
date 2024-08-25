sudo yum install -y gcc make  proj-devel  geos-devel  libxml2 libxml2-devel gdal-devel openssl openssl-devel gmp-devel boost-devel mpfr-devel zlib-devel libxml2-devel     sqlite-devel
 


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
wget http://download.osgeo.org/proj/proj-6.3.1.tar.gz
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
wget  https://github.com/protocolbuffers/protobuf/releases/download/v3.15.3/protobuf-all-3.15.3.tar.gz
tar -zxvf protobuf-all-3.15.3.tar.gz
cd protobuf-3.15.3
./configure
make
make install

export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig

 
## 安装protobuf-c
cd ..
wget  https://github.com/protobuf-c/protobuf-c/releases/download/v1.3.3/protobuf-c-1.3.3.tar.gz
tar -zxvf protobuf-c-1.3.3.tar.gz
cd protobuf-c-1.3.3
./configure
make
make install




/*
cd 
## 安装json-c
wget https://github.com/json-c/json-c/archive/refs/tags/json-c-0.17-20230812.tar.gz
 tar -zxvf json-c-json-c-0.17-20230812.tar.gz 
cd json-c-json-c-0.17-20230812/
./configure
make
make install
*/



## 安装gdal
wget https://github.com/OSGeo/gdal/releases/download/v3.4.3/gdal-3.4.3.tar.gz
 tar -zxvf gdal-3.4.3.tar.gz 
 cd  gdal-3.4.3
./configure LDFLAGS="-L/usr/local/lib" CPPFLAGS="-I/usr/local/include"
make
make install



## 安装CGAL
cd .. 
wget   https://github.com/CGAL/cgal/releases/download/releases%2FCGAL-4.14.3/CGAL-4.14.3.tar.xz
tar -xvf CGAL-4.14.3.tar.xz
cd CGAL-4.14.3
mkdir build && cd build
cmake ..
make
make install

   
## 安装SFCGAL
wget https://codeload.github.com/Oslandia/SFCGAL/tar.gz/refs/tags/v1.3.7
tar -zxvf tar -zxvf v1.3.7 
cd SFCGAL-1.3.7/
mkdir build && cd build
cmake .. 
make
make install

ln -s /usr/local/lib64/libSFCGAL.so /usr/local/lib/libSFCGAL.so
ln -s /usr/local/lib64/libSFCGAL.so.1 /usr/local/lib/libSFCGAL.so.1
 



## 安装pcre
cd ../..
wget  http://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz
tar -zxvf pcre-8.45.tar.gz 
cd pcre-8.45
./configure 
make
make install



## 安装postgis

tar -zxvf postgis-3.4.2.tar.gz 
cd postgis-3.4.2/ 
./configure --with-pgconfig=/home/postgres/pg/bin/pg_config 
make 
make install 


chown -R postgres:postgres /home/postgres


LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:$PGHOME/lib:$LD_LIBRARY_PATH
 ldconfig
重启数据库
pg_ctl restart 
 
 