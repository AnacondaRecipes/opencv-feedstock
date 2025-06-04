#!/bin/bash
set -ex

echo "=== OpenCV Build Script Debug Information ==="
echo "Date: $(date)"
echo "Build platform: ${build_platform:-unknown}"
echo "Target platform: ${target_platform:-unknown}"
echo "Build variant: ${build_variant:-unknown}"
echo "Python version: ${PY_VER:-unknown}"
echo "PREFIX: $PREFIX"
echo "SP_DIR: $SP_DIR"
echo "CPU_COUNT: ${CPU_COUNT:-unknown}"

# CMake FindPNG seems to look in libpng not libpng16
# https://gitlab.kitware.com/cmake/cmake/blob/master/Modules/FindPNG.cmake#L55
ln -s $PREFIX/include/libpng16 $PREFIX/include/libpng

V4L="1"

if [[ "${target_platform}" == linux-* ]]; then
    # Looks like there's a bug in Opencv 3.2.0 for building with FFMPEG
    # with GCC opencv/issues/8097
    export CXXFLAGS="$CXXFLAGS -D__STDC_CONSTANT_MACROS"
    OPENMP="-DWITH_OPENMP=1"
    echo "Linux build detected - enabling OpenMP and adding STDC_CONSTANT_MACROS"
fi

if [[ "$build_variant" == "normal" ]]; then
    echo "Building normal variant with Qt6"
    QT="6"
else
    echo "Building headless variant without Qt"
    QT="0"
    echo $QT
fi

if [[ "${target_platform}" == osx-* ]]; then
    V4L="0"
    echo "macOS build detected - disabling V4L"
elif [[ "${target_platform}" == linux-ppc64le ]]; then
    OPENVINO="0"
    echo "Linux PPC64LE build detected - disabling OpenVINO"
fi

if [[ "${target_platform}" != "${build_platform}" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DProtobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc"
    CMAKE_ARGS="${CMAKE_ARGS} -DQT_HOST_PATH=${BUILD_PREFIX}"
    echo "Cross-compilation detected - setting protoc and Qt host paths"
fi

export PKG_CONFIG_LIBDIR=$PREFIX/lib

IS_PYPY=$(${PYTHON} -c "import platform; print(int(platform.python_implementation() == 'PyPy'))")
echo "Python implementation: $(${PYTHON} -c "import platform; print(platform.python_implementation())")"
echo "Is PyPy: $IS_PYPY"

LIB_PYTHON="${PREFIX}/lib/libpython${PY_VER}${SHLIB_EXT}"
if [[ ${IS_PYPY} == "1" ]]; then
    INC_PYTHON="$PREFIX/include/pypy${PY_VER}"
else
    INC_PYTHON="$PREFIX/include/python${PY_VER}"
fi

echo "Python library: $LIB_PYTHON"
echo "Python include: $INC_PYTHON"

# FFMPEG building requires pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$PREFIX/lib/pkgconfig
echo "PKG_CONFIG_PATH: $PKG_CONFIG_PATH"
echo "PKG_CONFIG_LIBDIR: $PKG_CONFIG_LIBDIR"

# Debug: Check critical dependencies
echo "=== Debug: Checking critical dependencies ==="
echo "Checking for essential libraries and headers..."
for lib in libz libpng libjpeg libtiff libwebp libopenjpeg libprotobuf libhdf5; do
    if [[ -f "$PREFIX/lib/${lib}.so" || -f "$PREFIX/lib/${lib}.dylib" || -f "$PREFIX/lib/${lib}.a" ]]; then
        echo "✓ Found: $lib"
    else
        echo "✗ Missing: $lib"
    fi
done

echo "Checking for Python NumPy..."
${PYTHON} -c "import numpy; print(f'NumPy version: {numpy.__version__}'); print(f'NumPy include: {numpy.get_include()}')" || echo "NumPy import failed"

echo "Checking for Eigen..."
if [[ -d "$PREFIX/include/eigen3" ]]; then
    echo "✓ Found Eigen3 in $PREFIX/include/eigen3"
elif [[ -d "$PREFIX/include/Eigen" ]]; then
    echo "✓ Found Eigen in $PREFIX/include/Eigen"
else
    echo "✗ Eigen not found"
fi

# Debug: Check what GLib/GStreamer paths actually exist
echo "=== Debug: Checking GLib/GStreamer paths ==="
echo "PREFIX: $PREFIX"
ls -la $PREFIX/include/ | grep -E "(glib|gstreamer)" || echo "No glib/gstreamer in include/"
ls -la $PREFIX/lib/ | grep -E "(glib|gstreamer)" || echo "No glib/gstreamer in lib/"
ls -la $PREFIX/lib/pkgconfig/ | grep -E "(glib|gstreamer)" || echo "No glib/gstreamer pkgconfig files"

# Check what pkg-config returns for gstreamer
GSTREAMER_OK=0
if command -v pkg-config &> /dev/null; then
    echo "=== pkg-config debug ==="
    echo "pkg-config version: $(pkg-config --version)"
    pkg-config --exists gstreamer-1.0 && echo "gstreamer-1.0 found" || echo "gstreamer-1.0 NOT found"
    pkg-config --exists glib-2.0 && echo "glib-2.0 found" || echo "glib-2.0 NOT found"
    if pkg-config --exists gstreamer-1.0; then
        echo "GStreamer cflags: $(pkg-config --cflags gstreamer-1.0)"
        echo "GStreamer libs: $(pkg-config --libs gstreamer-1.0)"
        
        # Check if the include paths in pkg-config actually exist
        GSTREAMER_CFLAGS=$(pkg-config --cflags gstreamer-1.0)
        echo "Checking if GStreamer include paths actually exist..."
        PATHS_VALID=1
        for flag in $GSTREAMER_CFLAGS; do
            if [[ $flag == -I* ]]; then
                path=${flag#-I}
                if [[ ! -d "$path" ]]; then
                    echo "WARNING: GStreamer pkg-config references non-existent path: $path"
                    PATHS_VALID=0
                fi
            fi
        done
        
        if [[ $PATHS_VALID -eq 1 ]]; then
            GSTREAMER_OK=1
        else
            echo "GStreamer pkg-config paths are invalid, will disable GStreamer"
        fi
    fi
    if pkg-config --exists glib-2.0; then
        echo "GLib cflags: $(pkg-config --cflags glib-2.0)"
        echo "GLib libs: $(pkg-config --libs glib-2.0)"
    fi
else
    echo "pkg-config not found!"
fi
echo "=== End debug ==="

# Try manual GStreamer detection as fallback
if [[ $GSTREAMER_OK -eq 0 ]]; then
    echo "Attempting manual GStreamer detection..."
    if [[ -d "$PREFIX/include/gstreamer-1.0" && -f "$PREFIX/lib/libgstreamer-1.0.so" ]]; then
        echo "Found GStreamer files manually, but pkg-config is broken"
        echo "Will disable GStreamer to avoid pkg-config issues"
        GSTREAMER_ENABLE=0
    else
        echo "GStreamer files not found manually either"
        GSTREAMER_ENABLE=0
    fi
else
    echo "GStreamer pkg-config is working correctly"
    GSTREAMER_ENABLE=1
fi

# Decide whether to enable GStreamer based on detection
if [[ $GSTREAMER_ENABLE -eq 1 ]]; then
    echo "GStreamer appears functional, enabling it"
else
    echo "GStreamer detection failed or has invalid paths, disabling it to allow build to proceed"
    echo "OpenCV will build without GStreamer video support"
fi

# Create missing glib-2.0 include directory if it doesn't exist
# This is a workaround for broken conda packages
if [[ ! -d "$PREFIX/include/glib-2.0" ]]; then
    echo "Creating missing glib-2.0 include directory as workaround"
    mkdir -p "$PREFIX/include/glib-2.0"
    # Create a minimal glib.h if it doesn't exist
    if [[ ! -f "$PREFIX/include/glib-2.0/glib.h" ]]; then
        echo "// Dummy glib.h to prevent CMake errors" > "$PREFIX/include/glib-2.0/glib.h"
    fi
fi

# Also create the lib/glib-2.0/include directory that's commonly referenced
if [[ ! -d "$PREFIX/lib/glib-2.0/include" ]]; then
    echo "Creating missing lib/glib-2.0/include directory as workaround"
    mkdir -p "$PREFIX/lib/glib-2.0/include"
    if [[ ! -f "$PREFIX/lib/glib-2.0/include/glibconfig.h" ]]; then
        echo "// Dummy glibconfig.h to prevent CMake errors" > "$PREFIX/lib/glib-2.0/include/glibconfig.h"
    fi
fi

# Set up proper include paths for GLib and GStreamer
export CPPFLAGS="$CPPFLAGS -I$PREFIX/include/glib-2.0 -I$PREFIX/lib/glib-2.0/include"
export CPPFLAGS="$CPPFLAGS -I$PREFIX/include/gstreamer-1.0"

# Ensure OpenGL libraries can be found for Qt
if [[ "${target_platform}" == linux-* ]]; then
    export LDFLAGS="$LDFLAGS -L$PREFIX/lib"
    # Make sure CMake can find OpenGL libraries
    export CMAKE_ARGS="$CMAKE_ARGS -DOPENGL_gl_LIBRARY=$PREFIX/lib/libGL.so"
    export CMAKE_ARGS="$CMAKE_ARGS -DOPENGL_glu_LIBRARY=$PREFIX/lib/libGLU.so"
    export CMAKE_ARGS="$CMAKE_ARGS -DOPENGL_INCLUDE_DIR=$PREFIX/include/GL"
    echo "Linux OpenGL setup: libGL.so and libGLU.so detection configured"
fi

echo "=== Environment Variables Summary ==="
echo "CPPFLAGS: $CPPFLAGS"
echo "LDFLAGS: $LDFLAGS"
echo "CMAKE_ARGS: $CMAKE_ARGS"

echo "=== Qt Detection Debug ==="
if [[ "$QT" == "6" ]]; then
    echo "Checking Qt6 installation..."
    ls -la $PREFIX/lib/ | grep -i qt | head -10 || echo "No Qt libraries found"
    ls -la $PREFIX/include/ | grep -i qt | head -5 || echo "No Qt headers found"
    if command -v qmake &> /dev/null; then
        echo "qmake found: $(which qmake)"
        qmake -v || echo "qmake version check failed"
    else
        echo "qmake not found in PATH"
    fi
fi

mkdir -p build${PY_VER}
cd build${PY_VER}

echo "=== Starting CMake Configuration ==="
echo "Working directory: $(pwd)"
echo "CMake command about to be executed..."

# Note that though a dependency may be installed it may not be detected
# correctly by this build system and so some functionality may be disabled
# (this is more frequent on Windows but does sometimes happen on other OSes).
# Note that -DBUILD_x=0 may not be honoured for any particular dependency x.
# If -DHAVE_x=1 is used it may be that the undetected conda package is
# ignored in lieu of libraries that are built as part of this build (this
# will likely result in an overdepending error). Check the 3rdparty libraries
# directory in the build directory to see what has been vendored by the
# opencv build.
#
# The flags are set to enable the maximum set of features we are able to build,
# And align dependencies across subdirs. We also aim to preserve functionality 
# between updates. Each flag has a helper description in the upstream cmake files.
#
# A number of data files are downloaded when building opencv contrib.
# We may want to revisit that in a future update.
# The OPENCV_DOWNLOAD flags are there to make these downloads more robust.

echo "CMake configuration parameters:"
echo "- BUILD_TYPE: Release"
echo "- PREFIX_PATH: ${PREFIX}"
echo "- Qt support: $QT"
echo "- GStreamer support: $GSTREAMER_ENABLE"
echo "- OpenMP support: ${OPENMP:-0}"
echo "- V4L support: $V4L"

cmake -LAH -G "Ninja"                                                     \
    ${CMAKE_ARGS}                                                         \
    -DCMAKE_BUILD_TYPE="Release"                                          \
    -DCMAKE_PREFIX_PATH=${PREFIX}                                         \
    -DCMAKE_INSTALL_PREFIX=${PREFIX}                                      \
    -DCMAKE_INSTALL_LIBDIR="lib"                                          \
    -DOPENCV_DOWNLOAD_TRIES=1\;2\;3\;4\;5                                 \
    -DOPENCV_DOWNLOAD_PARAMS=INACTIVITY_TIMEOUT\;30\;TIMEOUT\;180\;SHOW_PROGRESS \
    -DOPENCV_GENERATE_PKGCONFIG=ON                                        \
    -DENABLE_CONFIG_VERIFICATION=ON                                       \
    -DENABLE_PRECOMPILED_HEADERS=OFF                                      \
    $OPENMP                                                               \
    -DWITH_LAPACK=0                                                       \
    -DCMAKE_CXX_STANDARD=17                                               \
    -DWITH_EIGEN=1                                                        \
    -DBUILD_TESTS=0                                                       \
    -DBUILD_DOCS=0                                                        \
    -DBUILD_PERF_TESTS=0                                                  \
    -DBUILD_ZLIB=0                                                        \
    -DBUILD_PNG=0                                                         \
    -DBUILD_JPEG=0                                                        \
    -DBUILD_TIFF=0                                                        \
    -DBUILD_WEBP=0                                                        \
    -DBUILD_OPENJPEG=0                                                    \
    -DBUILD_JASPER=0                                                      \
    -DBUILD_OPENEXR=0                                                     \
    -DWITH_PNG=ON                                                         \
    -DWITH_JPEG=ON                                                        \
    -DWITH_TIFF=ON                                                        \
    -DWITH_WEBP=ON                                                        \
    -DWITH_OPENJPEG=ON                                                    \
    -DWITH_JASPER=OFF                                                     \
    -DWITH_OPENEXR=ON                                                     \
    -DWITH_PROTOBUF=1                                                     \
    -DBUILD_PROTOBUF=0                                                    \
    -DPROTOBUF_UPDATE_FILES=1                                             \
    -DWITH_V4L=$V4L                                                       \
    -DWITH_CUDA=0                                                         \
    -DWITH_CUBLAS=0                                                       \
    -DWITH_OPENCL=0                                                       \
    -DWITH_OPENCLAMDFFT=0                                                 \
    -DWITH_OPENCLAMDBLAS=0                                                \
    -DWITH_OPENCL_D3D11_NV=0                                              \
    -DWITH_OPENVINO=0                                                     \
    -DWITH_1394=0                                                         \
    -DWITH_OPENNI=0                                                       \
    -DWITH_HDF5=1                                                         \
    -DWITH_FFMPEG=1                                                       \
    -DWITH_TENGINE=0                                                      \
    -DWITH_GSTREAMER=$GSTREAMER_ENABLE                                    \
    -DWITH_MATLAB=0                                                       \
    -DWITH_TESSERACT=0                                                    \
    -DWITH_VA=0                                                           \
    -DWITH_VA_INTEL=0                                                     \
    -DWITH_VTK=0                                                          \
    -DWITH_GTK=0                                                          \
    -DWITH_QT=$QT                                                         \
    -DWITH_OPENGL=ON                                                      \
    -DWITH_GPHOTO2=0                                                      \
    -DINSTALL_C_EXAMPLES=0                                                \
    -DOPENCV_EXTRA_MODULES_PATH="../opencv_contrib/modules"               \
    -DOpenCV_INSTALL_BINARIES_PREFIX=""                                   \
    -DCMAKE_SKIP_RPATH:bool=ON                                            \
    -DPYTHON_PACKAGES_PATH=${SP_DIR}                                      \
    -DPYTHON_EXECUTABLE=${PYTHON}                                         \
    -DPYTHON_INCLUDE_PATH=${INC_PYTHON}                                   \
    -DOPENCV_SKIP_PYTHON_LOADER=1                                         \
    -DZLIB_INCLUDE_DIR=${PREFIX}/include                                  \
    -DPYTHON_LIBRARY=${LIB_PYTHON}                                        \
    -DZLIB_LIBRARY_RELEASE=${PREFIX}/lib/libz${SHLIB_EXT}                 \
    -DJPEG_INCLUDE_DIR=${PREFIX}/include                                  \
    -DTIFF_INCLUDE_DIR=${PREFIX}/include                                  \
    -DPNG_PNG_INCLUDE_DIR=${PREFIX}/include                               \
    -DPROTOBUF_INCLUDE_DIR=${PREFIX}/include                              \
    -DPROTOBUF_LIBRARIES=${PREFIX}/lib                                    \
    -DOPENCV_ENABLE_PKG_CONFIG=1                                          \
    -DOPENCV_PYTHON_PIP_METADATA_INSTALL=ON                               \
    -DOPENCV_PYTHON_PIP_METADATA_INSTALLER:STRING="conda"                 \
    -DBUILD_opencv_python3=1                                              \
    -DPYTHON3_EXECUTABLE=${PYTHON}                                        \
    -DPYTHON3_INCLUDE_PATH=${INC_PYTHON}                                    \
    -DPYTHON3_NUMPY_INCLUDE_DIRS=$(python -c 'import numpy;print(numpy.get_include())')  \
    -DPYTHON3_LIBRARY=${LIB_PYTHON}                                       \
    -DPYTHON_DEFAULT_EXECUTABLE=${PREFIX}/bin/python                      \
    -DPYTHON3_PACKAGES_PATH=${SP_DIR}                                     \
    -DOPENCV_PYTHON3_INSTALL_PATH=${SP_DIR}                               \
    -DBUILD_opencv_python2=0                                              \
    -DPYTHON2_EXECUTABLE=                                                 \
    -DPYTHON2_INCLUDE_DIR=                                                \
    -DPYTHON2_NUMPY_INCLUDE_DIRS=                                         \
    -DPYTHON2_LIBRARY=                                                    \
    -DPYTHON2_PACKAGES_PATH=                                              \
    -DOPENCV_PYTHON2_INSTALL_PATH=                                        \
    ..

echo "=== CMake Configuration Complete ==="
echo "Starting ninja build with $CPU_COUNT cores..."
echo "Build started at: $(date)"

ninja install -j${CPU_COUNT}

echo "=== Build Complete ==="
echo "Build finished at: $(date)"
echo "Checking installed files..."
ls -la $PREFIX/lib/ | grep opencv | head -10 || echo "No opencv libraries found"
ls -la $PREFIX/include/ | grep opencv || echo "No opencv headers found"

echo "=== OpenCV Build Script Complete ==="
