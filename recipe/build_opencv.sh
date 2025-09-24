#!/bin/bash
set -ex

# CMake FindPNG seems to look in libpng not libpng16
# https://gitlab.kitware.com/cmake/cmake/blob/master/Modules/FindPNG.cmake#L55
ln -s $PREFIX/include/libpng16 $PREFIX/include/libpng

V4L="1"

if [[ "${target_platform}" == linux-* ]]; then
    # Looks like there's a bug in Opencv 3.2.0 for building with FFMPEG
    # with GCC opencv/issues/8097
    export CXXFLAGS="$CXXFLAGS -D__STDC_CONSTANT_MACROS"
    OPENMP="-DWITH_OPENMP=1"
elif [[ "${target_platform}" == osx-* ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -D_LIBCPP_DISABLE_AVAILABILITY=ON -DOPENCV_SKIP_LINK_NO_UNDEFINED=ON -DOPENCV_SKIP_LINK_AS_NEEDED=ON -DCPU_BASELINE_DISABLE=NEON_BF16"
    V4L="0"
fi

if [[ "$build_variant" == "normal" ]]; then
    echo "Building normal variant with Qt${QT}"
else
    echo "Building headless variant without Qt"
fi

if [[ "$QT" == "6" ]]; then
    # https://github.com/conda-forge/qt-main-feedstock/issues/332
    sed -i.bak '/INTERFACE_COMPILE_DEFINITIONS/d' "${PREFIX}/lib/cmake/Qt6Test/Qt6TestTargets.cmake"
    rm "${PREFIX}/lib/cmake/Qt6Test/Qt6TestTargets.cmake.bak"
fi

if [[ "${target_platform}" != "${build_platform}" ]]; then
    CMAKE_ARGS="${CMAKE_ARGS} -DProtobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc"
    CMAKE_ARGS="${CMAKE_ARGS} -DQT_HOST_PATH=${BUILD_PREFIX}"
fi

export PKG_CONFIG_LIBDIR=$PREFIX/lib

IS_PYPY=$(${PYTHON} -c "import platform; print(int(platform.python_implementation() == 'PyPy'))")

LIB_PYTHON="${PREFIX}/lib/libpython${PY_VER}${SHLIB_EXT}"
if [[ ${IS_PYPY} == "1" ]]; then
    INC_PYTHON="$PREFIX/include/pypy${PY_VER}"
else
    INC_PYTHON="$PREFIX/include/python${PY_VER}"
fi

# FFMPEG building requires pkgconfig
export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$PREFIX/lib/pkgconfig

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

cmake -LAH -B build -G "Ninja" -S .                                                     \
    ${CMAKE_ARGS}                                                                       \
    -DCMAKE_BUILD_TYPE="Release"                                                        \
    -DCMAKE_PREFIX_PATH=${PREFIX}                                                       \
    -DCMAKE_INSTALL_PREFIX=${PREFIX}                                                    \
    -DCMAKE_INSTALL_LIBDIR="lib"                                                        \
    -DOPENCV_DOWNLOAD_TRIES=1\;2\;3\;4\;5                                               \
    -DOPENCV_DOWNLOAD_PARAMS=INACTIVITY_TIMEOUT\;30\;TIMEOUT\;180\;SHOW_PROGRESS        \
    -DOPENCV_GENERATE_PKGCONFIG=ON                                                      \
    -DENABLE_CONFIG_VERIFICATION=ON                                                     \
    -DENABLE_PRECOMPILED_HEADERS=OFF                                                    \
    ${OPENMP}                                                                           \
    -DWITH_LAPACK=0                                                                     \
    -DCMAKE_CXX_STANDARD=17                                                             \
    -DWITH_AVIF=1                                                                       \
    -DWITH_EIGEN=1                                                                      \
    -DBUILD_TESTS=0                                                                     \
    -DBUILD_DOCS=0                                                                      \
    -DBUILD_PERF_TESTS=0                                                                \
    -DBUILD_ZLIB=0                                                                      \
    -DBUILD_PNG=0                                                                       \
    -DBUILD_JPEG=0                                                                      \
    -DBUILD_TIFF=0                                                                      \
    -DBUILD_WEBP=0                                                                      \
    -DBUILD_OPENJPEG=0                                                                  \
    -DBUILD_JASPER=0                                                                    \
    -DBUILD_OPENEXR=0                                                                   \
    -DWITH_PNG=ON                                                                       \
    -DWITH_JPEG=ON                                                                      \
    -DWITH_TIFF=ON                                                                      \
    -DWITH_WEBP=ON                                                                      \
    -DWITH_OPENJPEG=ON                                                                  \
    -DWITH_JASPER=0                                                                     \
    -DWITH_OPENEXR=ON                                                                   \
    -DWITH_PROTOBUF=1                                                                   \
    -DBUILD_PROTOBUF=0                                                                  \
    -DPROTOBUF_UPDATE_FILES=1                                                           \
    -DWITH_V4L=$V4L                                                                     \
    -DWITH_CUDA=0                                                                       \
    -DWITH_CUBLAS=0                                                                     \
    -DWITH_OPENCL=0                                                                     \
    -DWITH_OPENCLAMDFFT=0                                                               \
    -DWITH_OPENCLAMDBLAS=0                                                              \
    -DWITH_OPENCL_D3D11_NV=0                                                            \
    -DWITH_OPENVINO=0                                                                   \
    -DWITH_1394=0                                                                       \
    -DWITH_OPENNI=0                                                                     \
    -DWITH_HDF5=1                                                                       \
    -DWITH_FFMPEG=1                                                                     \
    -DWITH_TENGINE=0                                                                    \
    -DWITH_GSTREAMER=0                                                                  \
    -DWITH_MATLAB=0                                                                     \
    -DWITH_TESSERACT=0                                                                  \
    -DWITH_VA=0                                                                         \
    -DWITH_VA_INTEL=0                                                                   \
    -DWITH_VTK=0                                                                        \
    -DWITH_GTK=0                                                                        \
    -DWITH_QT=$QT                                                                       \
    -DQT_SKIP_DEFAULT_TESTCASE_DIRS=0                                                   \
    -DWITH_QTTEST=OFF                                                                   \
    -DWITH_OPENGL=ON                                                                    \
    -DWITH_GPHOTO2=0                                                                    \
    -DWITH_OBSENSOR=0                                                                   \
    -DINSTALL_C_EXAMPLES=0                                                              \
    -DOPENCV_EXTRA_MODULES_PATH="${SRC_DIR}/opencv_contrib/modules"                     \
    -DOpenCV_INSTALL_BINARIES_PREFIX=""                                                 \
    -DCMAKE_SKIP_RPATH:bool=ON                                                          \
    -DPYTHON_PACKAGES_PATH=${SP_DIR}                                                    \
    -DPYTHON_EXECUTABLE=${PYTHON}                                                       \
    -DPYTHON_INCLUDE_PATH=${INC_PYTHON}                                                 \
    -DOPENCV_SKIP_PYTHON_LOADER=1                                                       \
    -DZLIB_INCLUDE_DIR=${PREFIX}/include                                                \
    -DPYTHON_LIBRARY=${LIB_PYTHON}                                                      \
    -DZLIB_LIBRARY_RELEASE=${PREFIX}/lib/libz${SHLIB_EXT}                               \
    -DJPEG_INCLUDE_DIR=${PREFIX}/include                                                \
    -DTIFF_INCLUDE_DIR=${PREFIX}/include                                                \
    -DPNG_PNG_INCLUDE_DIR=${PREFIX}/include                                             \
    -DPROTOBUF_INCLUDE_DIR=${PREFIX}/include                                            \
    -DPROTOBUF_LIBRARIES=${PREFIX}/lib                                                  \
    -DOPENCV_ENABLE_PKG_CONFIG=1                                                        \
    -DOPENCV_PYTHON_PIP_METADATA_INSTALL=ON                                             \
    -DOPENCV_PYTHON_PIP_METADATA_INSTALLER:STRING="conda"                               \
    -DBUILD_opencv_python3=1                                                            \
    -DPYTHON3_EXECUTABLE=${PYTHON}                                                      \
    -DPYTHON3_INCLUDE_PATH=${INC_PYTHON}                                                \
    -DPYTHON3_NUMPY_INCLUDE_DIRS=$(python -c 'import numpy;print(numpy.get_include())') \
    -DPYTHON3_LIBRARY=${LIB_PYTHON}                                                     \
    -DPYTHON_DEFAULT_EXECUTABLE=${PREFIX}/bin/python                                    \
    -DPYTHON3_PACKAGES_PATH=${SP_DIR}                                                   \
    -DOPENCV_PYTHON3_INSTALL_PATH=${SP_DIR}                                             \
    -DBUILD_opencv_python2=0                                                            \
    -DPYTHON2_EXECUTABLE=                                                               \
    -DPYTHON2_INCLUDE_DIR=                                                              \
    -DPYTHON2_NUMPY_INCLUDE_DIRS=                                                       \
    -DPYTHON2_LIBRARY=                                                                  \
    -DPYTHON2_PACKAGES_PATH=                                                            \
    -DOPENCV_PYTHON2_INSTALL_PATH=                                                      

cmake --build build --target install -j${CPU_COUNT}
