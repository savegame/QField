set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_BUILD_TYPE release)

set(ENV{CXXFLAGS} "-fstack-protector-strong")
set(ENV{CFLAGS} "-fstack-protector-strong")

if(PORT STREQUAL "proj4" OR PORT STREQUAL "proj")
set(ENV{CXXFLAGS} "-fstack-protector-strong -fsanitize=address -fno-omit-frame-pointer")
set(ENV{CFLAGS} "-fstack-protector-strong -fsanitize=address -fno-omit-frame-pointer")
set(ENV{LDFLAGS} "-fsanitize=address")
endif()

set(ENV{VCPKG_ANDROID_NATIVE_API_LEVEL} "27")

