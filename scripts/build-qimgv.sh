#!/bin/bash
set -e

CFL='-ffunction-sections -fdata-sections -O3 -pipe'
LDFL='-Wl,--gc-sections'

MSYS_DIR="/mingw64"
CUSTOM_QT_DIR="/mingw64"
OPENCV_DIR="/opencv-minimal-4.5.5"
SCRIPTS_DIR=$(dirname $(readlink -f $0))
SRC_DIR=$(dirname $SCRIPTS_DIR)
BUILD_DIR=$SRC_DIR/build
EXT_DIR=$SRC_DIR/_external
rm -rf "$EXT_DIR"
mkdir "$EXT_DIR"
MPV_DIR=$EXT_DIR/mpv

# ------------------------------------------------------------------------------
echo "PREPARING BUILD DIR"
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

# ------------------------------------------------------------------------------
echo "UPDATING DEPENDENCY LIST"
wget --progress=dot:mega -O $BUILD_DIR/msys2-build-deps.txt https://raw.githubusercontent.com/easymodo/qimgv-deps-bin/main/msys2-build-deps.txt
wget --progress=dot:mega -O $BUILD_DIR/msys2-dll-deps.txt https://raw.githubusercontent.com/easymodo/qimgv-deps-bin/main/msys2-dll-deps.txt

# ------------------------------------------------------------------------------
echo "INSTALLING MSYS2 BUILD DEPS"
MSYS_DEPS=$(cat $BUILD_DIR/msys2-build-deps.txt | sed 's/\n/ /')
pacman -S $MSYS_DEPS --noconfirm --needed

# ------------------------------------------------------------------------------
echo "GETTING OpenCV"
mkdir -p $OPENCV_DIR
cd $OPENCV_DIR
wget --progress=dot:mega -O opencv-minimal-4.5.5-x64.7z https://github.com/easymodo/qimgv-deps-bin/releases/download/x64/opencv-minimal-4.5.5-x64.7z
7z x opencv-minimal-4.5.5-x64.7z -y
rm opencv-minimal-4.5.5-x64.7z

# ------------------------------------------------------------------------------
echo "GETTING MPV"
mkdir -p $MPV_DIR
cd $MPV_DIR
wget --progress=dot:mega -O mpv-x64.7z https://github.com/easymodo/qimgv-deps-bin/releases/download/x64/mpv-x86_64-20230402-git-0f13c38.7z
7z x mpv-x64.7z -y
rm mpv-x64.7z

# ------------------------------------------------------------------------------
echo "BUILDING qimgv"
sed -i 's|opencv4/||' $SRC_DIR/qimgv/3rdparty/QtOpenCV/cvmatandqimage.{h,cpp}
cmake -S $SRC_DIR -B $BUILD_DIR -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=$CUSTOM_QT_DIR \
    -DOpenCV_DIR=$OPENCV_DIR \
    -DOPENCV_SUPPORT=ON \
    -DVIDEO_SUPPORT=ON \
    -DMPV_DIR=$MPV_DIR \
    -DCMAKE_CXX_FLAGS="$CFL" -DCMAKE_EXE_LINKER_FLAGS="$LDFL"
ninja -C $BUILD_DIR

# ------------------------------------------------------------------------------
echo "BUILDING IMAGEFORMATS (Qt6)"
cd $EXT_DIR
git clone --depth 1 https://github.com/novomesk/qt-jpegxl-image-plugin.git
cd qt-jpegxl-image-plugin
rm -rf build
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_MAJOR_VERSION=6 \
    -DCMAKE_PREFIX_PATH=$CUSTOM_QT_DIR
ninja -C build

cd $EXT_DIR
git clone https://github.com/novomesk/qt-avif-image-plugin
cd qt-avif-image-plugin
rm -rf build
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DQT_MAJOR_VERSION=6 \
    -DCMAKE_PREFIX_PATH=$CUSTOM_QT_DIR
ninja -C build

cd $EXT_DIR
git clone https://github.com/Skycoder42/QtApng.git
cd QtApng
rm -rf build
mkdir build && cd build
$CUSTOM_QT_DIR/bin/qmake6.exe ..
mingw32-make -j4

cd $EXT_DIR
git clone https://github.com/jakar/qt-heif-image-plugin.git
cd qt-heif-image-plugin
rm -rf build
cmake -S . -B build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=$CUSTOM_QT_DIR
ninja -C build

cd $EXT_DIR
git clone https://gitlab.com/mardy/qtraw
cd qtraw
rm -rf build
mkdir build && cd build
$CUSTOM_QT_DIR/bin/qmake6.exe .. DEFINES+="LIBRAW_WIN32_CALLS=1"
mingw32-make -j4

# ------------------------------------------------------------------------------
echo "PACKAGING"
cd $SRC_DIR
BUILD_NAME=qimgv-x64_$(git describe --tags)
PACKAGE_DIR=$SRC_DIR/$BUILD_NAME
rm -rf $PACKAGE_DIR
mkdir $PACKAGE_DIR

cp $BUILD_DIR/qimgv/qimgv.exe $PACKAGE_DIR
mkdir $PACKAGE_DIR/plugins
cp $BUILD_DIR/plugins/player_mpv/player_mpv.dll $PACKAGE_DIR/plugins
cp -r $BUILD_DIR/qimgv/translations/ $PACKAGE_DIR/

# Qt6 DLLs
cd $CUSTOM_QT_DIR/bin
cp Qt6Core.dll Qt6Gui.dll Qt6PrintSupport.dll Qt6Svg.dll Qt6Widgets.dll $PACKAGE_DIR
cd $CUSTOM_QT_DIR/plugins
cp -r iconengines imageformats printsupport styles $PACKAGE_DIR
mkdir -p $PACKAGE_DIR/platforms
cp platforms/qwindows.dll $PACKAGE_DIR/platforms

# MSYS DLLs
MSYS_DLLS=$(cat $BUILD_DIR/msys2-dll-deps.txt | sed 's/\n/ /')
cd $MSYS_DIR/bin
cp $MSYS_DLLS $PACKAGE_DIR

# ✅ 手动复制 QUIC/SSL 依赖 DLL（避免缺 libngtcp2_crypto_ossl.dll）
cp $MSYS_DIR/bin/libngtcp2*.dll $PACKAGE_DIR || true
cp $MSYS_DIR/bin/libnghttp3*.dll $PACKAGE_DIR || true
cp $MSYS_DIR/bin/libssl*.dll $PACKAGE_DIR || true
cp $MSYS_DIR/bin/libcrypto*.dll $PACKAGE_DIR || true

# Imageformats plugins
cp $EXT_DIR/qt-jpegxl-image-plugin/build/bin/imageformats/libqjpegxl6.dll $PACKAGE_DIR/imageformats
cp $EXT_DIR/qt-avif-image-plugin/build/bin/imageformats/libqavif6.dll $PACKAGE_DIR/imageformats
cp $EXT_DIR/QtApng/build/plugins/imageformats/qapng.dll $PACKAGE_DIR/imageformats
cp $EXT_DIR/qt-heif-image-plugin/build/bin/imageformats/libqheif.dll $PACKAGE_DIR/imageformats
cp $EXT_DIR/qtraw/build/src/imageformats/qtraw.dll $PACKAGE_DIR/imageformats

# OpenCV & MPV
cd $OPENCV_DIR/x64/mingw/bin
cp libopencv_core455.dll libopencv_imgproc455.dll $PACKAGE_DIR
cd $MPV_DIR/bin/x86_64
cp mpv.exe libmpv-2.dll $PACKAGE_DIR

# misc
mkdir -p $PACKAGE_DIR/cache $PACKAGE_DIR/conf $PACKAGE_DIR/thumbnails
cp -r $SRC_DIR/qimgv/distrib/mimedata/data $PACKAGE_DIR

cd $SRC_DIR
echo "✅ PACKAGING DONE"
