@echo ON
setlocal enabledelayedexpansion

if "%build_variant%" == "normal" (
  echo "Building normal variant"
  set QT_VERSION=6
) else (
  echo "Building headless variant"
  set QT_VERSION=0
)

for /F "tokens=1,2 delims=. " %%a in ("%PY_VER%") do (
   set "PY_MAJOR=%%a"
   set "PY_MINOR=%%b"
)
set PY_LIB=python%PY_MAJOR%%PY_MINOR%.lib

mkdir build%PY_MAJOR%%PY_MINOR%
cd build%PY_MAJOR%%PY_MINOR%

:: Workaround for building LAPACK headers with C++17
:: see https://github.com/conda-forge/opencv-feedstock/pull/363#issuecomment-1604972688
set "CXXFLAGS=%CXXFLAGS% -D_CRT_USE_C_COMPLEX_H"

:: CMake/OpenCV like Unix-style paths for some reason.
set UNIX_PREFIX=%PREFIX:\=/%
set UNIX_LIBRARY_PREFIX=%LIBRARY_PREFIX:\=/%
set UNIX_LIBRARY_BIN=%LIBRARY_BIN:\=/%
set UNIX_LIBRARY_INC=%LIBRARY_INC:\=/%
set UNIX_LIBRARY_LIB=%LIBRARY_LIB:\=/%
set UNIX_SP_DIR=%SP_DIR:\=/%
set UNIX_SRC_DIR=%SRC_DIR:\=/%

:: FFMPEG building requires pkgconfig
set PKG_CONFIG_PATH=%UNIX_LIBRARY_PREFIX%/lib/pkgconfig

rem Note that though a dependency may be installed it may not be detected
rem correctly by this build system and so some functionality may be disabled
rem (this is more frequent on Windows but does sometimes happen on other OSes).
rem Note that -DBUILD_x=0 may not be honoured for any particular dependency x.
rem If -DHAVE_x=1 is used it may be that the undetected conda package is
rem ignored in lieu of libraries that are built as part of this build (this
rem will likely result in an overdepending error). Check the 3rdparty libraries
rem directory in the build directory to see what has been vendored by the
rem opencv build.
rem
rem The flags are set to enable the maximum set of features we are able to build,
rem And align dependencies across subdirs. We also aim to preserve functionality 
rem between updates. Each flag has a helper description in the upstream cmake files.
rem
rem A number of data files are downloaded when building opencv contrib.
rem We may want to revisit that in a future update.
rem The OPENCV_DOWNLOAD flags are there to make these downloads more robust.
rem ENABLE_PRECOMPILED_HEADERS is deprecated on win and set to OFF as such.
cmake -LAH -G "Ninja"                                                               ^
    -DCMAKE_BUILD_TYPE="Release"                                                    ^
    -DCMAKE_INSTALL_PREFIX=%UNIX_LIBRARY_PREFIX%                                    ^
    -DCMAKE_PREFIX_PATH=%UNIX_LIBRARY_PREFIX%                                       ^
    -DOPENCV_CONFIG_INSTALL_PATH=cmake                                              ^
    -DOPENCV_BIN_INSTALL_PATH=bin                                                   ^
    -DOPENCV_LIB_INSTALL_PATH=lib                                                   ^
    -DOPENCV_GENERATE_SETUPVARS=OFF                                                 ^
    -DOPENCV_DOWNLOAD_TRIES=1;2;3;4;5                                               ^
    -DOPENCV_DOWNLOAD_PARAMS=INACTIVITY_TIMEOUT;30;TIMEOUT;180;SHOW_PROGRESS        ^
    -DOPENCV_GENERATE_PKGCONFIG=OFF                                                 ^
    -DENABLE_CONFIG_VERIFICATION=ON                                                 ^
    -DENABLE_PRECOMPILED_HEADERS=OFF                                                ^
    -DWITH_LAPACK=0                                                                 ^
    -DCMAKE_CXX_STANDARD=17                                                         ^
    -DWITH_EIGEN=1                                                                  ^
    -DBUILD_TESTS=0                                                                 ^
    -DBUILD_DOCS=0                                                                  ^
    -DBUILD_PERF_TESTS=0                                                            ^
    -DBUILD_ZLIB=0                                                                  ^
    -DBUILD_PNG=0                                                                   ^
    -DBUILD_JPEG=0                                                                  ^
    -DBUILD_TIFF=0                                                                  ^
    -DBUILD_WEBP=0                                                                  ^
    -DBUILD_OPENJPEG=0                                                              ^
    -DBUILD_JASPER=0                                                                ^
    -DBUILD_OPENEXR=0                                                               ^
    -DWITH_PNG=ON                                                                   ^
    -DWITH_JPEG=ON                                                                  ^
    -DWITH_TIFF=ON                                                                  ^
    -DWITH_WEBP=ON                                                                  ^
    -DWEBP_LIBRARY=%PREFIX%/Library/lib/libwebp.lib                                 ^
    -DWEBP_INCLUDE_DIR=%PREFIX%/Library/include                                     ^
    -DWITH_OPENJPEG=ON                                                              ^
    -DWITH_JASPER=OFF                                                               ^
    -DWITH_OPENEXR=ON                                                               ^
    -DWITH_PROTOBUF=1                                                               ^
    -DBUILD_PROTOBUF=0                                                              ^
    -DPROTOBUF_UPDATE_FILES=1                                                       ^
    -DBUILD_opencv_bioinspired=0                                                    ^
    -DWITH_CUDA=0                                                                   ^
    -DWITH_CUBLAS=0                                                                 ^
    -DWITH_OPENCL=0                                                                 ^
    -DWITH_OPENCLAMDFFT=0                                                           ^
    -DWITH_OPENCLAMDBLAS=0                                                          ^
    -DWITH_OPENCL_D3D11_NV=0                                                        ^
    -DWITH_OPENVINO=0                                                               ^
    -DWITH_1394=0                                                                   ^
    -DWITH_OPENNI=0                                                                 ^
    -DWITH_HDF5=1                                                                   ^
    -DWITH_FFMPEG=0                                                                 ^
    -DWITH_TENGINE=0                                                                ^
    -DWITH_GSTREAMER=1                                                              ^
    -DWITH_MATLAB=0                                                                 ^
    -DWITH_TESSERACT=0                                                              ^
    -DWITH_VA=0                                                                     ^
    -DWITH_VA_INTEL=0                                                               ^
    -DWITH_VTK=0                                                                    ^
    -DWITH_GTK=0                                                                    ^
    -DWITH_QT=%QT_VERSION%                                                          ^
    -DWITH_GPHOTO2=0                                                                ^
    -DWITH_WIN32UI=0                                                                ^
    -DINSTALL_C_EXAMPLES=0                                                          ^
    -DOPENCV_EXTRA_MODULES_PATH=%UNIX_SRC_DIR%/opencv_contrib/modules               ^
    -DPYTHON_EXECUTABLE=%UNIX_PREFIX%/python                                        ^
    -DPYTHON_INCLUDE_PATH=%UNIX_PREFIX%/include                                     ^
    -DPYTHON_PACKAGES_PATH=%UNIX_SP_DIR%                                            ^
    -DPYTHON_LIBRARY=%UNIX_PREFIX%/libs/%PY_LIB%                                    ^
    -DOPENCV_SKIP_PYTHON_LOADER=1                                                   ^
    -DBUILD_opencv_python2=0                                                        ^
    -DPYTHON2_EXECUTABLE=""                                                         ^
    -DPYTHON2_INCLUDE_DIR=""                                                        ^
    -DPYTHON2_NUMPY_INCLUDE_DIRS=""                                                 ^
    -DPYTHON2_LIBRARY=""                                                            ^
    -DPYTHON2_PACKAGES_PATH=""                                                      ^
    -DOPENCV_PYTHON2_INSTALL_PATH=""                                                ^
    -DBUILD_opencv_python3=1                                                        ^
    -DPYTHON3_EXECUTABLE=%UNIX_PREFIX%/python                                       ^
    -DPYTHON3_INCLUDE_PATH=%UNIX_PREFIX%/include                                    ^
    -DPYTHON3_LIBRARY=%UNIX_PREFIX%/libs/%PY_LIB%                                   ^
    -DPYTHON3_PACKAGES_PATH=%UNIX_SP_DIR%                                           ^
    -DOPENCV_PYTHON3_INSTALL_PATH=%UNIX_SP_DIR%                                     ^
    -DOPENCV_PYTHON_PIP_METADATA_INSTALL=ON                                         ^
    -DOPENCV_PYTHON_PIP_METADATA_INSTALLER:STRING="conda"                           ^
    ..
if %ERRORLEVEL% neq 0 (type CMakeError.log && exit 1)

cmake --build . --target install --config Release
if %ERRORLEVEL% neq 0 exit 1
