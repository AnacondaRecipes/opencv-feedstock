#!/bin/bash

DEBUG_CMAKE_BUILD_SYSTEM=yes
declare -a CMAKE_DEBUG_ARGS PYTHON_CMAKE_ARGS VAR_DEPS DEPS_DEFAULTS CMAKE_EXTRA_ARGS

if [[ ${DEBUG_CMAKE_BUILD_SYSTEM} == yes ]]; then
#  CMAKE_DEBUG_ARGS+=("--debug-trycompile")
#  CMAKE_DEBUG_ARGS+=("-Wdev")
#  CMAKE_DEBUG_ARGS+=("--debug-output")
#  CMAKE_DEBUG_ARGS+=("--trace")
  CMAKE_DEBUG_ARGS+=("-DOPENCV_CMAKE_DEBUG_MESSAGES=1")
fi

echo "PYTHON_CMAKE_ARGS="
echo "${PYTHON_CMAKE_ARGS[@]}"

if [[ "${target_platform}" != "${build_platform}" ]]; then
  # enabling explicitly the use of an external Protobuf, see https://github.com/conda-forge/opencv-feedstock/pull/269
  CMAKE_ARGS="${CMAKE_ARGS} -DProtobuf_PROTOC_EXECUTABLE=$BUILD_PREFIX/bin/protoc"
fi

# Set defaults for dependencies that change across OSes
# This should match the meta.yaml deps section
if [[ "$build_variant" == "normal" ]]; then
  echo "Building normal variant"
  VAR_DEPS=(EIGEN FFMPEG PROTOBUF GSTREAMER OPENJPEG OPENMP QT WEBP)
  DEPS_DEFAULTS=(1 0 0 1 1 1 5 0)
else
  echo "Building headless variant"
  VAR_DEPS=(EIGEN FFMPEG PROTOBUF GSTREAMER OPENJPEG OPENMP WEBP)
  DEPS_DEFAULTS=(1 0 0 1 1 1 0)
fi
if [[ ${#DEPS_DEFAULTS[@]} != ${#VAR_DEPS[@]} ]];then echo Setting defaults failed: Length mismatch;exit 1; fi
for ii in ${!VAR_DEPS[@]};do
    eval "WITH_${VAR_DEPS[ii]}=${DEPS_DEFAULTS[ii]}"
done

# Assemble CMAKE_EXTRA_ARGS  with OS-specific settings
echo "Platform: ${target_platform}"
if [[ ${target_platform} == osx-* ]]; then
  CMAKE_EXTRA_ARGS+=("-DCMAKE_OSX_SYSROOT=${CONDA_BUILD_SYSROOT}")
  CMAKE_EXTRA_ARGS+=("-DZLIB_LIBRARY_RELEASE=${PREFIX}/lib/libz.dylib")
  WITH_OPENMP=0
  if [[ ${target_platform} == osx-arm64 ]]; then
    WITH_OPENJPEG=0
  fi
elif [[ ${target_platform} == linux-64 ]];then
  # pkgconfig for FFMPEG building FFMPEG test needs __STDC_CONSTANT_MACROS enabled.
  export CXXFLAGS="$CXXFLAGS -D__STDC_CONSTANT_MACROS"
  # for qt the value is coerced to boolean but it also used to set the version
  # of the QT cmake config file looked for
  WITH_PROTOBUF=1
  WITH_WEBP=1
  WITH_FFMPEG=1
  
  # Set explicitly where to find the Jasper library (optimized).
  CMAKE_ARGS="${CMAKE_ARGS} -DJASPER_LIBRARY_RELEASE=${PREFIX}/lib/libjasper.so"
elif [[ ${target_platform} == linux-aarch64 ]];then
    echo aarch64
    CMAKE_ARGS="${CMAKE_ARGS} -DJASPER_LIBRARY_RELEASE=${PREFIX}/lib/libjasper.so"
else
    echo Unsupported platform
fi

# append dependencies to CMAKE_EXTRA_ARGS
for dep in "${VAR_DEPS[@]}";do
    varname=WITH_${dep}
    CMAKE_EXTRA_ARGS+=("-D${varname}=${!varname}")
done
# append debug args
CMAKE_EXTRA_ARGS+=("${CMAKE_DEBUG_ARGS[@]}")
echo "CMake_EXTRA_ARGS : ${CMAKE_EXTRA_ARGS[@]}"

export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$PREFIX/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$PREFIX/lib

mkdir -p build
cd build
cmake .. -GNinja                                                        \
  ${CMAKE_ARGS}                                                         \
  "${CMAKE_EXTRA_ARGS[@]}"                                              \
  "${PYTHON_CMAKE_ARGS[@]}"                                             \
  -DCMAKE_CXX_STANDARD=17                                               \
  -DCMAKE_BUILD_TYPE="Release"                                          \
  -DCMAKE_PREFIX_PATH=${PREFIX}                                         \
  -DCMAKE_INSTALL_PREFIX=${PREFIX}                                      \
  -DCMAKE_INSTALL_LIBDIR="lib"                                          \
  -DOPENCV_DOWNLOAD_TRIES=1\;2\;3\;4\;5                                 \
  -DOPENCV_DOWNLOAD_PARAMS=INACTIVITY_TIMEOUT\;30\;TIMEOUT\;180\;SHOW_PROGRESS \
  -DOPENCV_GENERATE_PKGCONFIG=ON                                          \
  -DBUILD_DOCS=0                                                          \
  -DBUILD_JASPER=0                                                        \
  -DBUILD_JPEG=0                                                          \
  -DBUILD_OPENJPEG=0                                                      \
  -DBUILD_LIBPROTOBUF_FROM_SOURCES=0                                      \
  -DBUILD_OPENEXR=ON                                                      \
  -DBUILD_PERF_TESTS=0                                                    \
  -DBUILD_PNG=0                                                           \
  -DBUILD_PROTOBUF=0                                                      \
  -DPROTOBUF_UPDATE_FILES=ON                                              \
  -DBUILD_TESTS=0                                                         \
  -DBUILD_TIFF=0                                                          \
  -DBUILD_ZLIB=0                                                          \
  -DBUILD_WEBP=0                                                          \
  -DBUILD_opencv_apps=OFF                                                 \
  -DCMAKE_CROSSCOMPILING=ON                                               \
  -DENABLE_CONFIG_VERIFICATION=ON                                         \
  -DENABLE_FLAKE8=0                                                       \
  -DENABLE_PYLINT=0                                                       \
  -DINSTALL_C_EXAMPLES=OFF                                                \
  -DINSTALL_PYTHON_EXAMPLES=ON                                            \
  -DOPENCV_EXTRA_MODULES_PATH="../opencv_contrib-${PKG_VERSION}/modules"  \
  -DOpenCV_INSTALL_BINARIES_PREFIX=""                                     \
  -DOPENCV_PYTHON_PIP_METADATA_INSTALL=ON                                 \
  -DOPENCV_PYTHON_PIP_METADATA_INSTALLER:STRING="conda"                   \
  -DBUILD_opencv_python3=1                                                \
  -DPYTHON3_EXECUTABLE=${PYTHON}                                          \
  -DPYTHON_DEFAULT_EXECUTABLE=${PREFIX}/bin/python                        \
  -DPYTHON3_PACKAGES_PATH=${SP_DIR}                                       \
  -DOPENCV_PYTHON3_INSTALL_PATH=${SP_DIR}                                 \
  -DWITH_1394=OFF                                                         \
  -DWITH_CUDA=OFF                                                         \
  -DWITH_GTK=OFF                                                          \
  -DWITH_ITT=OFF                                                          \
  -DWITH_JASPER=OFF                                                        \
  -DJASPER_INCLUDE_DIR=${PREFIX}/include \
  -DWITH_LAPACK=OFF                                                       \
  -DWITH_MATLAB=OFF                                                       \
  -DWITH_OPENCL=OFF                                                       \
  -DWITH_OPENCLAMDBLAS=OFF                                                \
  -DWITH_OPENCLAMDFFT=OFF                                                 \
  -DWITH_OPENNI=OFF                                                       \
  -DWITH_TESSERACT=OFF                                                    \
  -DWITH_VA=OFF                                                           \
  -DWITH_VA_INTEL=OFF                                                     \
  -DWITH_VTK=OFF                                                          \
  -DBUILD_opencv_python2=OFF


if [[ ! $? ]]; then
  echo "configure failed with $?"
  exit 1
fi

cmake --build .

