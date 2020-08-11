#!/bin/bash

#感谢 zark_fun 提供的脚本
#参照 https://gist.github.com/eminarcissus/108c2ac0c7c9124b65709b44edabd424 做的微调。
#zark_fun 的博客地址：https://blog.csdn.net/zhangkai19890929/article/details/85598493

# Builds a Libjpeg framework for the iPhone and the iPhone Simulator.
# Creates a set of universal libraries that can be used on an iPhone and in the
# iPhone simulator. Then creates a pseudo-framework to make using libjpeg in Xcode
# less painful.
#
# To configure the script, define:
#    IPHONE_SDKVERSION: iPhone SDK version (e.g. 8.0)
#
# Then go get the source tar.bz of the libjpeg you want to build, shove it in the
# same directory as this script, and run "bash libjpeg.sh". Grab a cuppa. And voila.
#===============================================================================

# 需要编译的libjpeg版本 可以在 http://www.ijg.org/files 看到所有libjpeg的版本
# 编译6.2版本会报错，因为没用到，没有研究
: ${LIB_VERSION:=9}

# Current iPhone SDK
# 自动获取当前版本，这个和你Xcode设置里面选择的 Command Line Tools 有关，建议不要使用
# : ${IPHONE_SDKVERSION:=`xcodebuild -showsdks | grep iphoneos | egrep "[[:digit:]]+\.[[:digit:]]+" -o | tail -1`}
# Specific iPhone SDK

# libjpeg最低支持的iOS系统，不要超过10，会提示不支持
: ${IPHONE_SDKVERSION:=8.0}

: ${XCODE_ROOT:=`xcode-select -print-path`}

: ${TARBALLDIR:=`pwd`}
: ${SRCDIR:=`pwd`/src}
: ${IOSBUILDDIR:=`pwd`/ios/build}
: ${OSXBUILDDIR:=`pwd`/osx/build}
: ${PREFIXDIR:=`pwd`/ios/prefix}
: ${IOSFRAMEWORKDIR:=`pwd`/ios/framework}
: ${OSXFRAMEWORKDIR:=`pwd`/osx/framework}

LIB_TARBALL=$TARBALLDIR/jpegsrc.v$LIB_VERSION.tar.gz
LIB_SRC=$SRCDIR/jpeg-${LIB_VERSION}

#===============================================================================
ARM_DEV_CMD="xcrun --sdk iphoneos"
SIM_DEV_CMD="xcrun --sdk iphonesimulator"

#===============================================================================
# Functions
#===============================================================================

abort()
{
    echo
    echo "Aborted: $@"
    exit 1
}

doneSection()
{
    echo
    echo "================================================================="
    echo "Done"
    echo
}

#===============================================================================

cleanEverythingReadyToStart()
{
    echo Cleaning everything before we start to build...

    rm -rf iphone-build iphonesim-build
    rm -rf $IOSBUILDDIR
    rm -rf $PREFIXDIR
    rm -rf $IOSFRAMEWORKDIR/$FRAMEWORK_NAME.framework

    doneSection
}

#===============================================================================

downloadLibjpeg()
{
    if [ ! -s $LIB_TARBALL ]; then
        echo "Downloading libjpeg ${LIB_VERSION}"
        curl -L -o $LIB_TARBALL http://www.ijg.org/files/jpegsrc.v${LIB_VERSION}.tar.gz
    fi

    doneSection
}

#===============================================================================

unpackLibjpeg()
{
    [ -f "$LIB_TARBALL" ] || abort "Source tarball missing."

    echo Unpacking libjpeg into $SRCDIR...

    [ -d $SRCDIR ]    || mkdir -p $SRCDIR
    [ -d $LIB_SRC ] || ( cd $SRCDIR; tar xfj $LIB_TARBALL )
    [ -d $LIB_SRC ] && echo "    ...unpacked as $LIB_SRC"

    doneSection
}

#===============================================================================

buildLibjpegForIPhoneOS()
{
    export CC=$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang
    export CC_BASENAME=clang

    export CXX=$XCODE_ROOT/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++
    export CXX_BASENAME=clang++

    #编译模拟器版本
    echo Building Libjpeg for iPhoneSimulator
    mkdir -p $LIB_SRC/iphonesim-build
    cd $LIB_SRC/iphonesim-build
    # 在我的电脑编译的时候报错，我把 iPhoneSimulator${IPHONE_SDKVERSION}.sdk 替换成了 iPhoneSimulator.sdk
    export CFLAGS="-O3 -arch i386 -arch x86_64 -isysroot $XCODE_ROOT/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk 
    -mios-simulator-version-min=${IPHONE_SDKVERSION}"
    ../configure --prefix=$PREFIXDIR/iphonesim-build --disable-dependency-tracking --enable-static=yes --enable-shared=no --host=i686-pc-none
    make
    make install
    doneSection

    #编译真机版本
    echo Building Libjpeg for iPhone
    mkdir -p $LIB_SRC/iphone-build
    cd $LIB_SRC/iphone-build
    # 在我的电脑编译的时候报错，我把 iPhoneOS${IPHONE_SDKVERSION}.sdk 替换成了 iPhoneOS.sdk
    export CFLAGS="-O3 -arch armv7 -arch armv7s -arch arm64 -isysroot $XCODE_ROOT/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk -mios-version-min=${IPHONE_SDKVERSION}"
    ../configure --host=arm-apple-darwin --prefix=$PREFIXDIR/iphone-build --disable-dependency-tracking --enable-static=yes --enable-shared=no
    make
    make install
    doneSection
}

#===============================================================================

scrunchAllLibsTogetherInOneLibPerPlatform()
{
    cd $PREFIXDIR

    # iOS Device
    mkdir -p $IOSBUILDDIR/armv7
    mkdir -p $IOSBUILDDIR/armv7s
    mkdir -p $IOSBUILDDIR/arm64

    # iOS Simulator
    mkdir -p $IOSBUILDDIR/i386
    mkdir -p $IOSBUILDDIR/x86_64

    echo Splitting all existing fat binaries...

    $ARM_DEV_CMD lipo "iphone-build/lib/libjpeg.a" -thin armv7 -o $IOSBUILDDIR/armv7/libjpeg.a
    $ARM_DEV_CMD lipo "iphone-build/lib/libjpeg.a" -thin armv7s -o $IOSBUILDDIR/armv7s/libjpeg.a
    $ARM_DEV_CMD lipo "iphone-build/lib/libjpeg.a" -thin arm64 -o $IOSBUILDDIR/arm64/libjpeg.a

    # 因为我的项目不支持模拟器，所以我把模拟器相关的代码注释掉了，需要的可以打开
    $SIM_DEV_CMD lipo "iphonesim-build/lib/libjpeg.a" -thin i386 -o $IOSBUILDDIR/i386/libjpeg.a
    $SIM_DEV_CMD lipo "iphonesim-build/lib/libjpeg.a" -thin x86_64 -o $IOSBUILDDIR/x86_64/libjpeg.a
}

#===============================================================================
# framework编译报错，因为我不需要framework版本，所以没有做研究，有解决这个问题的麻烦告诉我下。
buildFramework()
{
    : ${1:?}
    FRAMEWORKDIR=$1
    BUILDDIR=$2

    VERSION_TYPE=Alpha
    FRAMEWORK_NAME=libjpeg
    FRAMEWORK_VERSION=A

    FRAMEWORK_CURRENT_VERSION=$LIB_VERSION
    FRAMEWORK_COMPATIBILITY_VERSION=$LIB_VERSION

    FRAMEWORK_BUNDLE=$FRAMEWORKDIR/$FRAMEWORK_NAME.framework
    echo "Framework: Building $FRAMEWORK_BUNDLE from $BUILDDIR..."

    rm -rf $FRAMEWORK_BUNDLE

    echo "Framework: Setting up directories..."
    mkdir -p $FRAMEWORK_BUNDLE
    mkdir -p $FRAMEWORK_BUNDLE/Versions
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Resources
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Headers
    mkdir -p $FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/Documentation

    echo "Framework: Creating symlinks..."
    ln -s $FRAMEWORK_VERSION               $FRAMEWORK_BUNDLE/Versions/Current
    ln -s Versions/Current/Headers         $FRAMEWORK_BUNDLE/Headers
    ln -s Versions/Current/Resources       $FRAMEWORK_BUNDLE/Resources
    ln -s Versions/Current/Documentation   $FRAMEWORK_BUNDLE/Documentation
    ln -s Versions/Current/$FRAMEWORK_NAME $FRAMEWORK_BUNDLE/$FRAMEWORK_NAME

    FRAMEWORK_INSTALL_NAME=$FRAMEWORK_BUNDLE/Versions/$FRAMEWORK_VERSION/$FRAMEWORK_NAME

    echo "Lipoing library into $FRAMEWORK_INSTALL_NAME..."
    $ARM_DEV_CMD lipo -create $BUILDDIR/*/libjpeg.a -o "$FRAMEWORK_INSTALL_NAME" || abort "Lipo $1 failed"

    echo "Framework: Copying includes..."
    cp -r $PREFIXDIR/include/libjpeg/*  $FRAMEWORK_BUNDLE/Headers/

    echo "Framework: Creating plist..."
    cat > $FRAMEWORK_BUNDLE/Resources/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>CFBundleDevelopmentRegion</key>
<string>English</string>
<key>CFBundleExecutable</key>
<string>${FRAMEWORK_NAME}</string>
<key>CFBundleIdentifier</key>
<string>org.libjpeg</string>
<key>CFBundleInfoDictionaryVersion</key>
<string>6.0</string>
<key>CFBundlePackageType</key>
<string>FMWK</string>
<key>CFBundleSignature</key>
<string>????</string>
<key>CFBundleVersion</key>
<string>${FRAMEWORK_CURRENT_VERSION}</string>
</dict>
</plist>
EOF

    doneSection
}

#===============================================================================
# Execution starts here
#===============================================================================

mkdir -p $IOSBUILDDIR

# cleanEverythingReadyToStart #may want to comment if repeatedly running during dev

echo "LIB_VERSION:       $LIB_VERSION"
echo "LIB_SRC:           $LIB_SRC"
echo "IOSBUILDDIR:       $IOSBUILDDIR"
echo "PREFIXDIR:         $PREFIXDIR"
echo "IOSFRAMEWORKDIR:   $IOSFRAMEWORKDIR"
echo "IPHONE_SDKVERSION: $IPHONE_SDKVERSION"
echo "XCODE_ROOT:        $XCODE_ROOT"
echo

downloadLibjpeg
unpackLibjpeg
buildLibjpegForIPhoneOS
scrunchAllLibsTogetherInOneLibPerPlatform
buildFramework $IOSFRAMEWORKDIR $IOSBUILDDIR

echo "Completed successfully"

#===============================================================================
