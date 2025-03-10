set(QGIS_REF final-3_26_0)
set(QGIS_SHA512 0d307e5daaab32c96442f3428d1b59bb23fcf56b1afe2fd76ea9bdb4de1fadca328934bd0e5f5aed09850ed63a1585d026ae44d77f7204d40da9c1370363df6b)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO qgis/QGIS
    REF ${QGIS_REF}
    SHA512   ${QGIS_SHA512}
    HEAD_REF master
    PATCHES
        # Make qgis support python's debug library
        qgspython.patch
        gdal.patch
        keychain.patch
        libxml2.patch
        exiv2.patch
        androidextras.patch
        crssync.patch
        bigobj.patch
)

file(REMOVE ${SOURCE_PATH}/cmake/FindQtKeychain.cmake)
file(REMOVE ${SOURCE_PATH}/cmake/FindGDAL.cmake)
file(REMOVE ${SOURCE_PATH}/cmake/FindGEOS.cmake)
file(REMOVE ${SOURCE_PATH}/cmake/FindEXIV2.cmake)
file(REMOVE ${SOURCE_PATH}/cmake/FindExpat.cmake)
file(REMOVE ${SOURCE_PATH}/cmake/FindIconv.cmake)

vcpkg_find_acquire_program(FLEX)
vcpkg_find_acquire_program(BISON)
vcpkg_find_acquire_program(PYTHON3)
get_filename_component(PYTHON3_PATH ${PYTHON3} DIRECTORY)
vcpkg_add_to_path(${PYTHON3_PATH})
vcpkg_add_to_path(${PYTHON3_PATH}/Scripts)
set(PYTHON_EXECUTABLE ${PYTHON3})

list(APPEND QGIS_OPTIONS -DENABLE_TESTS:BOOL=OFF)
list(APPEND QGIS_OPTIONS -DWITH_QTWEBKIT:BOOL=OFF)
list(APPEND QGIS_OPTIONS -DWITH_GRASS7:BOOL=OFF)
list(APPEND QGIS_OPTIONS -DWITH_SPATIALITE:BOOL=ON)
list(APPEND QGIS_OPTIONS -DWITH_QSPATIALITE:BOOL=OFF)

if("opencl" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DUSE_OPENCL:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DUSE_OPENCL:BOOL=OFF)
endif()

if("bindings" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_BINDINGS:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_BINDINGS:BOOL=OFF)
endif()

if("gui" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_GUI:BOOL=ON)
else()
    if("desktop" IN_LIST FEATURES OR "customwidgets" IN_LIST FEATURES)
        message(FATAL_ERROR "If QGIS is built without gui, desktop and customwidgets cannot be built. Enable gui or disable customwidgets and desktop.")
    endif()
    list(APPEND QGIS_OPTIONS -DWITH_GUI:BOOL=OFF)
endif()

if("desktop" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_DESKTOP:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_DESKTOP:BOOL=OFF)
endif()

if("customwidgets" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_CUSTOM_WIDGETS:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_CUSTOM_WIDGETS:BOOL=OFF)
endif()

if("server" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_SERVER:BOOL=ON)
    if("bindings" IN_LIST FEATURES)
        list(APPEND QGIS_OPTIONS -DWITH_SERVER_PLUGINS:BOOL=ON)
    else()
        list(APPEND QGIS_OPTIONS -DWITH_SERVER_PLUGINS:BOOL=OFF)
    endif()
else()
    list(APPEND QGIS_OPTIONS -DWITH_SERVER:BOOL=OFF)
endif()

if("process" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_QGIS_PROCESS:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_QGIS_PROCESS:BOOL=OFF)
endif()

if("3d" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_3D:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_3D:BOOL=OFF)
endif()

if("quick" IN_LIST FEATURES)
    list(APPEND QGIS_OPTIONS -DWITH_QUICK:BOOL=ON)
else()
    list(APPEND QGIS_OPTIONS -DWITH_QUICK:BOOL=OFF)
endif()

# Configure debug and release library paths
macro(FIND_LIB_OPTIONS basename relname debname suffix libsuffix)
   file(TO_NATIVE_PATH "${CURRENT_INSTALLED_DIR}/lib/${VCPKG_TARGET_IMPORT_LIBRARY_PREFIX}${relname}${libsuffix}" ${basename}_LIBRARY_RELEASE)
   file(TO_NATIVE_PATH "${CURRENT_INSTALLED_DIR}/debug/lib/${VCPKG_TARGET_IMPORT_LIBRARY_PREFIX}${debname}${libsuffix}" ${basename}_LIBRARY_DEBUG)
   if( ${basename}_LIBRARY_DEBUG AND ${basename}_LIBRARY_RELEASE AND NOT ${basename}_LIBRARY_DEBUG STREQUAL ${basename}_LIBRARY_RELEASE )
        list(APPEND QGIS_OPTIONS_RELEASE -D${basename}_${suffix}:FILEPATH=${${basename}_LIBRARY_RELEASE})
        list(APPEND QGIS_OPTIONS_DEBUG -D${basename}_${suffix}:FILEPATH=${${basename}_LIBRARY_DEBUG})
   elseif( ${basename}_LIBRARY_RELEASE )
        list(APPEND QGIS_OPTIONS -D${basename}_${suffix}:FILEPATH=${${basename}_LIBRARY_RELEASE})
   elseif( ${basename}_LIBRARY_DEBUG )
        list(APPEND QGIS_OPTIONS -D${basename}_${suffix}:FILEPATH=${${basename}_LIBRARY_DEBUG})
   endif()
endmacro()

if (VCPKG_LIBRARY_LINKAGE STREQUAL "static")
  list(APPEND QGIS_OPTIONS -DFORCE_STATIC_LIBS=TRUE)
  list(APPEND QGIS_OPTIONS -DFORCE_STATIC_PROVIDERS=TRUE)
  # QGIS likes to install auth and providers to different locations on each platform
  # let's keep things clean and tidy and put them at a predictable location
  list(APPEND QGIS_OPTIONS -DQGIS_PLUGIN_SUBDIR=lib)
endif()

# By default QGIS installs includes into "include" on Windows and into "include/qgis" everywhere else
# let's keep things clean and tidy and put them at a predictable location
list(APPEND QGIS_OPTIONS -DQGIS_INCLUDE_SUBDIR=include/qgis)

if(VCPKG_TARGET_IS_WINDOWS)
    ##############################################################################
    #Install pip
    if(NOT EXISTS "${PYTHON3_PATH}/Scripts/pip.exe")
        MESSAGE(STATUS  "Install pip for Python Begin ...")
        vcpkg_download_distfile(
            GET_PIP_PATH
            URLS https://bootstrap.pypa.io/pip/3.5/get-pip.py
            FILENAME get-pip.py
            SHA512  a408dd74e69a2c3259e06669562bebfff676156a1a3b2f8ba6594ed308e3f94afdf79257688e59b02bf02bd7f6ecbea510fc6665b403149031f14bcc08308a47
        )

        vcpkg_execute_required_process(
            COMMAND "${PYTHON_EXECUTABLE}" "${GET_PIP_PATH}"
            WORKING_DIRECTORY ${PYTHON3_PATH}
            LOGNAME pip
        )

        vcpkg_execute_required_process(
            COMMAND "${PYTHON_EXECUTABLE}" -m pip install --upgrade pip
            WORKING_DIRECTORY ${PYTHON3_PATH}
            LOGNAME pip
        )
        MESSAGE(STATUS  "Install pip for Python End")
    endif (NOT EXISTS "${PYTHON3_PATH}/Scripts/pip.exe")
    ##############################################################################

    list(APPEND QGIS_OPTIONS -DBISON_EXECUTABLE="${BISON}")
    list(APPEND QGIS_OPTIONS -DFLEX_EXECUTABLE="${FLEX}")

    list(APPEND QGIS_OPTIONS -DPYUIC_PROGRAM=${PYTHON3_PATH}/Scripts/pyuic5.exe)
    list(APPEND QGIS_OPTIONS -DPYRCC_PROGRAM=${PYTHON3_PATH}/Scripts/pyrcc5.exe)
    list(APPEND QGIS_OPTIONS -DQT_LRELEASE_EXECUTABLE=${CURRENT_INSTALLED_DIR}/tools/qt5-tools/bin/lrelease.exe)

    # qgis_gui depends on Qt5UiTools, and Qt5UiTools is a static library.
    # If Qt5_EXCLUDE_STATIC_DEPENDENCIES is not set, it will add the QT release library that it depends on.
    # so that in debug mode, it will reference both the qt debug library and the release library.
    # In Debug mode, add Qt5_EXCLUDE_STATIC_DEPENDENCIES to avoid this bug
    list(APPEND QGIS_OPTIONS_DEBUG -DQt5_EXCLUDE_STATIC_DEPENDENCIES:BOOL=ON)

    FIND_LIB_OPTIONS(GDAL gdal gdald LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(GEOS geos_c geos_cd LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(GSL gsl gsld LIB ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(GSLCBLAS gslcblas gslcblasd LIB ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(POSTGRES libpq libpq LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(PROJ proj proj_d LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(PYTHON python39 python39_d LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(QCA qca qcad LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(QTKEYCHAIN qt5keychain qt5keychaind LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    FIND_LIB_OPTIONS(QSCINTILLA qscintilla2_qt5 qscintilla2_qt5d LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    if (VCPKG_LIBRARY_LINKAGE STREQUAL "static")
      FIND_LIB_OPTIONS(ZSTD zstd_static zstd_staticd LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    endif()
    if("server" IN_LIST FEATURES)
        FIND_LIB_OPTIONS(FCGI libfcgi libfcgi LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
        list(APPEND QGIS_OPTIONS -DFCGI_INCLUDE_DIR="${CURRENT_INSTALLED_DIR}/include/fastcgi")
    endif()
    if("gui" IN_LIST FEATURES)
        FIND_LIB_OPTIONS(QWT qwt qwtd LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
    endif()

    set(SPATIALINDEX_LIB_NAME spatialindex)
    if( VCPKG_TARGET_ARCHITECTURE STREQUAL "x64" OR VCPKG_TARGET_ARCHITECTURE STREQUAL "arm64" )
        set( SPATIALINDEX_LIB_NAME "spatialindex-64" )
    else()
        set( SPATIALINDEX_LIB_NAME "spatialindex-32" )
    endif()
    FIND_LIB_OPTIONS(SPATIALINDEX ${SPATIALINDEX_LIB_NAME} ${SPATIALINDEX_LIB_NAME}d LIBRARY ${VCPKG_TARGET_IMPORT_LIBRARY_SUFFIX})
else() # Build in UNIX
    list(APPEND QGIS_OPTIONS -DCMAKE_FIND_ROOT_PATH=$ENV{Qt5_DIR}) # for building with system Qt. Should find a nicer solution.
    list(APPEND QGIS_OPTIONS -DWITH_QTMOBILITY=OFF)
    list(APPEND QGIS_OPTIONS_DEBUG -DQT_INSTALL_LIBS:PATH=${CURRENT_INSTALLED_DIR}/debug/lib)
    list(APPEND QGIS_OPTIONS_RELEASE -DQT_INSTALL_LIBS:PATH=${CURRENT_INSTALLED_DIR}/lib)
    list(APPEND QGIS_OPTIONS -DGSL_CONFIG=" ")
    list(APPEND QGIS_OPTIONS -DGSL_INCLUDE_DIR:PATH=${CURRENT_INSTALLED_DIR}/include)
    list(APPEND QGIS_OPTIONS -DPROJ_INCLUDE_DIR:PATH=${CURRENT_INSTALLED_DIR}/include)
    list(APPEND QGIS_OPTIONS_DEBUG -DGSL_LIBRARIES:FILEPATH=${CURRENT_INSTALLED_DIR}/debug/lib/${VCPKG_TARGET_STATIC_LIBRARY_PREFIX}gsld${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX};${CURRENT_INSTALLED_DIR}/debug/lib/${VCPKG_TARGET_STATIC_LIBRARY_PREFIX}gslcblasd${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX})
    list(APPEND QGIS_OPTIONS -DPROJ_INCLUDE_DIR:PATH=${CURRENT_INSTALLED_DIR}/include)
    list(APPEND QGIS_OPTIONS_RELEASE -DQCA_LIBRARY=${CURRENT_INSTALLED_DIR}/lib/libqca.a)
    list(APPEND QGIS_OPTIONS_DEBUG -DQCA_LIBRARY=${CURRENT_INSTALLED_DIR}/debug/lib/libqca.a)
    list(APPEND QGIS_OPTIONS_RELEASE -DGSL_LIBRARIES:FILEPATH=${CURRENT_INSTALLED_DIR}/lib/${VCPKG_TARGET_STATIC_LIBRARY_PREFIX}gsl${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX} ${CURRENT_INSTALLED_DIR}/lib/${VCPKG_TARGET_STATIC_LIBRARY_PREFIX}gslcblas${VCPKG_TARGET_STATIC_LIBRARY_SUFFIX})
    list(APPEND QGIS_OPTIONS_DEBUG "-DCMAKE_CXX_STANDARD_LIBRARIES=${CURRENT_INSTALLED_DIR}/debug/lib/libgeos_cd.a ${CURRENT_INSTALLED_DIR}/debug/lib/libgeosd.a ${CURRENT_INSTALLED_DIR}/debug/lib/libfreexl.a ${CURRENT_INSTALLED_DIR}/debug/lib/libbz2d.a ${CURRENT_INSTALLED_DIR}/debug/lib/libgslcblasd.a $ENV{CMAKE_EXTRA_CXX_STANDARD_LIBRARIES}")
    list(APPEND QGIS_OPTIONS_RELEASE "-DCMAKE_CXX_STANDARD_LIBRARIES:FILEPATH=${CURRENT_INSTALLED_DIR}/lib/libgeos_c.a ${CURRENT_INSTALLED_DIR}/lib/libgeos.a ${CURRENT_INSTALLED_DIR}/lib/libfreexl.a ${CURRENT_INSTALLED_DIR}/lib/libbz2.a ${CURRENT_INSTALLED_DIR}/lib/libgslcblas.a $ENV{CMAKE_EXTRA_CXX_STANDARD_LIBRARIES}")
    if("server" IN_LIST FEATURES)
        FIND_LIB_OPTIONS(FCGI fcgi fcgi LIBRARY ${VCPKG_TARGET_SHARED_LIBRARY_SUFFIX})
        list(APPEND QGIS_OPTIONS -DFCGI_INCLUDE_DIR="${CURRENT_INSTALLED_DIR}/include/fastcgi")
    endif()
    if(EXISTS "${CURRENT_INSTALLED_DIR}/debug/lib/libqt_poly2tri_debug.a")
        list(APPEND QGIS_OPTIONS -DWITH_INTERNAL_POLY2TRI=OFF)
        list(APPEND QGIS_OPTIONS -DPoly2Tri_INCLUDE_DIR:PATH=${CMAKE_CURRENT_LIST_DIR}/poly2tri)
        list(APPEND QGIS_OPTIONS_DEBUG -DPoly2Tri_LIBRARY:PATH=${CURRENT_INSTALLED_DIR}/debug/lib/libqt_poly2tri_debug.a) # static qt only
        list(APPEND QGIS_OPTIONS_RELEASE -DPoly2Tri_LIBRARY:PATH=${CURRENT_INSTALLED_DIR}/lib/libqt_poly2tri.a) # static qt only
    endif()
endif()

list(APPEND QGIS_OPTIONS -DQGIS_MACAPP_FRAMEWORK=FALSE)

if(VCPKG_TARGET_IS_IOS)
    list(APPEND QGIS_OPTIONS -DWITH_QT5SERIALPORT=FALSE)
    list(APPEND QGIS_OPTIONS -DWITH_AUTH=FALSE) # Trying to link shared libs will fail on ios because https://gist.github.com/agirault/3244bf956c2cad7217b148291135f85e (2.3)
endif()

vcpkg_configure_cmake(
    SOURCE_PATH ${SOURCE_PATH}
    #PREFER_NINJA
    OPTIONS ${QGIS_OPTIONS} 
    OPTIONS_DEBUG ${QGIS_OPTIONS_DEBUG}
    OPTIONS_RELEASE ${QGIS_OPTIONS_RELEASE}
)

vcpkg_install_cmake()

if(VCPKG_TARGET_IS_WINDOWS)
    function(copy_path basepath targetdir)
        file(GLOB ${basepath}_PATH ${CURRENT_PACKAGES_DIR}/${basepath}/*)
        if( ${basepath}_PATH )
            file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/${targetdir}/${PORT}/${basepath})
            file(COPY ${${basepath}_PATH} DESTINATION ${CURRENT_PACKAGES_DIR}/${targetdir}/${PORT}/${basepath})
        endif()
 
        if(EXISTS "${CURRENT_PACKAGES_DIR}/${basepath}/")
            file(REMOVE_RECURSE ${CURRENT_PACKAGES_DIR}/${basepath}/)
        endif()
    endfunction()

    file(GLOB QGIS_TOOL_PATH ${CURRENT_PACKAGES_DIR}/bin/*${VCPKG_TARGET_EXECUTABLE_SUFFIX} ${CURRENT_PACKAGES_DIR}/*${VCPKG_TARGET_EXECUTABLE_SUFFIX})
    if(QGIS_TOOL_PATH)
        file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin)
        file(COPY ${QGIS_TOOL_PATH} DESTINATION ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin)
        file(REMOVE_RECURSE ${QGIS_TOOL_PATH})
        file(GLOB QGIS_TOOL_PATH ${CURRENT_PACKAGES_DIR}/bin/* )
        file(COPY ${QGIS_TOOL_PATH} DESTINATION ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin)
    endif()
    
    file(GLOB QGIS_TOOL_PATH_DEBUG ${CURRENT_PACKAGES_DIR}/debug/bin/*${VCPKG_TARGET_EXECUTABLE_SUFFIX} ${CURRENT_PACKAGES_DIR}/debug/*${VCPKG_TARGET_EXECUTABLE_SUFFIX})
    if(QGIS_TOOL_PATH_DEBUG)
        if("debug-tools" IN_LIST FEATURES)
            file(MAKE_DIRECTORY ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin)
            file(COPY ${QGIS_TOOL_PATH_DEBUG} DESTINATION ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin)
            file(REMOVE_RECURSE ${QGIS_TOOL_PATH_DEBUG})
            file(GLOB QGIS_TOOL_PATH_DEBUG ${CURRENT_PACKAGES_DIR}/debug/bin/* )
            file(COPY ${QGIS_TOOL_PATH_DEBUG} DESTINATION ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin)
        else()
            file(REMOVE_RECURSE ${QGIS_TOOL_PATH_DEBUG})
        endif()
    endif()

    copy_path(doc share)
    copy_path(i18n share)
    copy_path(icons share)
    copy_path(images share)
    copy_path(plugins tools)
    copy_path(resources share)
    copy_path(svg share)
    
    # Extend vcpkg_copy_tool_dependencies to support the export of dll and exe dependencies in different directories to the same directory,
    # and support the copy of debug dependencies
    function(vcpkg_copy_tool_dependencies_ex TOOL_DIR OUTPUT_DIR SEARCH_DIR)
        find_program(PS_EXE powershell PATHS ${DOWNLOADS}/tool)
        if (PS_EXE-NOTFOUND)
            message(FATAL_ERROR "Could not find powershell in vcpkg tools, please open an issue to report this.")
        endif()
        macro(search_for_dependencies PATH_TO_SEARCH)
            file(GLOB TOOLS ${TOOL_DIR}/*.exe ${TOOL_DIR}/*.dll)
            foreach(TOOL ${TOOLS})
                vcpkg_execute_required_process(
                    COMMAND ${PS_EXE} -noprofile -executionpolicy Bypass -nologo
                        -file ${CMAKE_CURRENT_LIST_DIR}/applocal.ps1
                        -targetBinary ${TOOL}
                        -installedDir ${PATH_TO_SEARCH}
                        -outputDir    ${OUTPUT_DIR}
                    WORKING_DIRECTORY ${VCPKG_ROOT_DIR}
                    LOGNAME copy-tool-dependencies
                )
            endforeach()
        endmacro()
        search_for_dependencies(${CURRENT_PACKAGES_DIR}/${SEARCH_DIR})
        search_for_dependencies(${CURRENT_INSTALLED_DIR}/${SEARCH_DIR})
    endfunction()

    vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin bin)
    vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/tools/${PORT}/plugins ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin bin)
    if("debug-tools" IN_LIST FEATURES)
        vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin debug/bin)
        vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/plugins ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin debug/bin)
    endif()
    if("server" IN_LIST FEATURES)
        vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/tools/${PORT}/server ${CURRENT_PACKAGES_DIR}/tools/${PORT}/bin bin)
        if("debug-tools" IN_LIST FEATURES)
            vcpkg_copy_tool_dependencies_ex(${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/server ${CURRENT_PACKAGES_DIR}/debug/tools/${PORT}/bin debug/bin)
        endif()
    endif()
endif()

file(GLOB QGIS_CMAKE_PATH ${CURRENT_PACKAGES_DIR}/*.cmake)
if(QGIS_CMAKE_PATH)
    file(COPY ${QGIS_CMAKE_PATH} DESTINATION ${CURRENT_PACKAGES_DIR}/share/cmake/${PORT})
    file(REMOVE_RECURSE ${QGIS_CMAKE_PATH})
endif()

file(GLOB QGIS_CMAKE_PATH_DEBUG ${CURRENT_PACKAGES_DIR}/debug/*.cmake)
if( QGIS_CMAKE_PATH_DEBUG )
    file(REMOVE_RECURSE ${QGIS_CMAKE_PATH_DEBUG})
endif()

file(REMOVE_RECURSE
    ${CURRENT_PACKAGES_DIR}/debug/include
)
file(REMOVE_RECURSE # Added for debug porpose
    ${CURRENT_PACKAGES_DIR}/debug/share
)

configure_file("${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" "${CURRENT_PACKAGES_DIR}/share/${PORT}/vcpkg-cmake-wrapper.cmake" @ONLY)

# Handle copyright
file(INSTALL ${SOURCE_PATH}/COPYING DESTINATION ${CURRENT_PACKAGES_DIR}/share/${PORT} RENAME copyright)
