cmake_minimum_required(VERSION 3.14)

# Set up compiler
# This env var should be setup by tools, or we can potentially infer from XMOS_MAKE_PATH
# TODO remove hardcoded xs3a
include("$ENV{XMOS_CMAKE_PATH}/xmos_cmake_toolchain/xs3a.cmake")

if(PROJECT_SOURCE_DIR)
    message(FATAL_ERROR "xmos_utils.cmake must be included before a project definition")
endif()

# Check that supported bitstream has been specified
#include("bitstream_src/supported_hw.cmake")
#if(DEFINED BOARD)
#    if(${BOARD} IN_LIST SUPPORTED_HW)
#        include("bitstream_src/${BOARD}/board.cmake")
#    else()
#        message("\nConfiguration for ${BOARD} not found.\nPreconfigured bitstreams are:")
#        foreach(HW ${SUPPORTED_HW})
#            message("\t${HW}")
#        endforeach()
#        message(FATAL_ERROR "")
#    endif()
#else()
#    message("\n-DBOARD must be specified.\nPreconfigured bitstreams are:")
#    foreach(HW ${SUPPORTED_HW})
#        message("\t${HW}")
#    endforeach()
#    message(FATAL_ERROR "")
#endif()

## Setup at caller scope

# Set up some XMOS specific variables
set(FULL 1 )
set(BITSTREAM_ONLY 2 )
set(BSP_ONLY 3 )
define_property(TARGET PROPERTY OPTIONAL_HEADERS BRIEF_DOCS "Contains list of optional headers." FULL_DOCS "Contains a list of optional headers.  The application level should search through all app includes and define D__[header]_h_exists__ for each header that is in both the app and optional headers.")
define_property(GLOBAL PROPERTY XMOS_TARGETS_LIST BRIEF_DOCS "brief" FULL_DOCS "full")

# Setup lib build output
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/libs")

# Setup build output
file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/${BOARD}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/${BOARD}")

function (GET_ALL_VARS_STARTING_WITH _prefix _varResult)
    get_cmake_property(_vars VARIABLES)
    string (REGEX MATCHALL "(^|;)${_prefix}[A-Za-z0-9_\\.]*" _matchedVars "${_vars}")
    set (${_varResult} ${_matchedVars} PARENT_SCOPE)
endfunction()

macro(add_app_file_flags)
    foreach(SRC_FILE_PATH ${ALL_SRCS_PATH})
        
        # Over-ride file flags if APP_COMPILER_FLAGS_<source_file> is set
        get_filename_component(SRC_FILE ${SRC_FILE_PATH} NAME)
        foreach(FLAG_FILE ${APP_FLAG_FILES})
            string(COMPARE EQUAL ${FLAG_FILE} ${SRC_FILE} _cmp)
            if(_cmp)
                set(flags ${APP_COMPILER_FLAGS_${FLAG_FILE}})
                set_source_files_properties(${SRC_FILE_PATH} PROPERTIES COMPILE_FLAGS ${flags})
                message(STATUS "MATCH" ${SRC_FILE_PATH})
                message(STATUS ${APP_COMPILER_FLAGS_${FLAG_FILE}})
            endif()
        endforeach()
    endforeach()
endmacro() 

## Registers an application and it's dependencies
function(XMOS_REGISTER_APP)
    if(NOT APP_HW_TARGET)
        message(FATAL_ERROR "APP_HW_TARGET not set in application Cmakelists")
    endif()

    if(NOT APP_COMPILER_FLAGS)
        set(APP_COMPILER_FLAGS "-DF") #TODO FIXME HACK
    endif()

    ## Populate build flag for hardware target
    if(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/${APP_HW_TARGET})
        get_filename_component(HW_ABS_PATH ${CMAKE_CURRENT_SOURCE_DIR}/${APP_HW_TARGET} ABSOLUTE)
        set(APP_TARGET_COMPILER_FLAG ${HW_ABS_PATH})
    else()
        set(APP_TARGET_COMPILER_FLAG "-target=${APP_HW_TARGET}")
    endif()

    #if(DEFINED THIS_XCORE_TILE)
    #    list(APPEND APP_COMPILER_FLAGS "-DTHIS_XCORE_TILE=${THIS_XCORE_TILE}")
    #endif()

    if(NOT APP_XC_SRCS)
        file(GLOB_RECURSE APP_XC_SRCS src/*.xc)
    endif()

    if(NOT APP_CXX_SRCS)
        file(GLOB_RECURSE APP_CXX_SRCS src/*.cpp)
    endif()

    if(NOT APP_C_SRCS)
        file(GLOB_RECURSE APP_C_SRCS src/*.c)
    endif()

    if(NOT APP_ASM_SRCS)
        file(GLOB_RECURSE APP_ASM_SRCS src/*.S)
    endif()

    set(ALL_SRCS_PATH ${APP_XC_SRCS} ${APP_ASM_SRCS} ${APP_C_SRCS} ${APP_CXX_SRCS})

    set(LIB_NAME ${PROJECT_NAME}_LIB)
    set(LIB_VERSION ${PROJECT_VERSION})
    set(LIB_ADD_COMPILER_FLAGS ${APP_COMPILER_FLAGS} ${BOARD_COMPILE_FLAGS})
    set(LIB_XC_SRCS ${APP_XC_SRCS} ${BOARD_XC_SRCS})
    set(LIB_CXX_SRCS ${APP_CXX_SRCS} ${BOARD_CXX_SRCS})
    set(LIB_C_SRCS ${APP_C_SRCS} ${BOARD_C_SRCS})
    set(LIB_ASM_SRCS ${APP_ASM_SRCS} ${BOARD_ASM_SRCS})
    set(LIB_INCLUDES ${APP_INCLUDES} ${BOARD_INCLUDES})
    set(LIB_DEPENDENT_MODULES ${APP_DEPENDENT_MODULES})
    set(LIB_OPTIONAL_HEADERS "")
    set(LIB_FILE_FLAGS "")

    XMOS_REGISTER_MODULE("silent")

    get_target_property(${PROJECT_NAME}_LIB_SRCS ${PROJECT_NAME}_LIB SOURCES)
    get_target_property(${PROJECT_NAME}_LIB_INCS ${PROJECT_NAME}_LIB INCLUDE_DIRECTORIES)
    get_target_property(${PROJECT_NAME}_LIB_OPTINCS ${PROJECT_NAME}_LIB OPTIONAL_HEADERS)
    get_target_property(${PROJECT_NAME}_LIB_FILE_FLAGS ${PROJECT_NAME}_LIB FILE_FLAGS)

    set(APP_SOURCES ${APP_XC_SRCS} ${BOARD_XC_SRCS} ${APP_CXX_SRCS} ${BOARD_CXX_SRCS} ${APP_C_SRCS} ${BOARD_C_SRCS} ${APP_ASM_SRCS} ${BOARD_ASM_SRCS})
    set(APP_INCLUDES ${APP_INCLUDES} ${BOARD_INCLUDES})

    get_property(XMOS_TARGETS_LIST GLOBAL PROPERTY XMOS_TARGETS_LIST)

    foreach(lib ${XMOS_TARGETS_LIST})
        get_target_property(inc ${lib} INCLUDE_DIRECTORIES)
        list(APPEND APP_INCLUDES ${inc})
    endforeach()

    list(REMOVE_DUPLICATES APP_SOURCES)
    list(REMOVE_DUPLICATES APP_INCLUDES)

    # Only define header exists, if header optional
    foreach(inc ${APP_INCLUDES})
        file(GLOB headers ${inc}/*.h)
        foreach(header ${headers})
            get_filename_component(name ${header} NAME)
            list(FIND ${PROJECT_NAME}_LIB_OPTINCS ${name} FOUND)
            if(${FOUND} GREATER -1)
                get_filename_component(name_we ${header} NAME_WE)
                list(APPEND HEADER_EXIST_FLAGS -D__${name_we}_h_exists__)
            endif()
        endforeach()
    endforeach()

    # Find all build configs
    GET_ALL_VARS_STARTING_WITH("APP_COMPILER_FLAGS_" APP_COMPILER_FLAGS_VARS)

    message(STATUS ${APP_COMPILER_FLAGS_VARS})

    set(APP_CONFIGS "")
    set(APP_FLAG_FILES "")
    foreach(APP_FLAGS ${APP_COMPILER_FLAGS_VARS})
        string(REPLACE "APP_COMPILER_FLAGS_" "" APP_FLAGS ${APP_FLAGS})

        # Ignore any "file" flags 
        if(NOT APP_FLAGS MATCHES "\\.")
            list(APPEND APP_CONFIGS ${APP_FLAGS})
        else()
            list(APPEND APP_FLAG_FILES ${APP_FLAGS})
        endif()
        
    endforeach()

    # Somewhat follow the strategy of xcommon here with a config named "Default" 
    list(LENGTH APP_CONFIGS CONFIGS_COUNT) 
    if(${CONFIGS_COUNT} EQUAL 0)
        list(APPEND APP_CONFIGS "DEFAULT") 
    endif()

    set(DEPS_TO_LINK "")
    foreach(target ${XMOS_TARGETS_LIST})
        target_include_directories(${target} PRIVATE ${APP_INCLUDES})
        target_compile_options(${target} BEFORE PRIVATE ${APP_COMPILE_FLAGS})
        add_dependencies(${PROJECT_NAME} ${target})
        list(APPEND DEPS_TO_LINK ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/lib${target}.a)
    endforeach()
    list(REMOVE_DUPLICATES DEPS_TO_LINK)

    message(STATUS "Found build configs:")
    
    # For each build config set up targets and compiler flags etc
    #TODO -DCONFIG=${APP_CONFIG}
    foreach(APP_CONFIG ${APP_CONFIGS})
        message(STATUS ${APP_CONFIG})
        # Check for the "Default" config we created if user didn't specify any configs
        if(${APP_CONFIG} STREQUAL "DEFAULT")
            add_executable(${PROJECT_NAME})
            target_sources(${PROJECT_NAME} PRIVATE ${APP_SOURCES})
            target_include_directories(${PROJECT_NAME} PRIVATE ${APP_INCLUDES})
            
            target_compile_options(${PROJECT_NAME} PRIVATE ${APP_COMPILER_FLAGS} ${APP_TARGET_COMPILER_FLAG} ${HEADER_EXISTS_FLAGS})
            
            target_link_libraries(${PROJECT_NAME} PRIVATE ${DEPS_TO_LINK})
            target_link_options(${PROJECT_NAME} PRIVATE ${APP_TARGET_COMPILER_FLAG} ${HEADER_EXISTS_FLAGS})

            # Setup build output
            file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/")
            set_target_properties(${PROJECT_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/")
        else()
            add_executable(${PROJECT_NAME}_${APP_CONFIG})
            target_sources(${PROJECT_NAME}_${APP_CONFIG} PRIVATE ${APP_SOURCES})
            target_include_directories(${PROJECT_NAME}_${APP_CONFIG} PRIVATE ${APP_INCLUDES})
            
            target_compile_options(${PROJECT_NAME}_${APP_CONFIG} PRIVATE ${APP_COMPILER_FLAGS_${APP_CONFIG}}  ${APP_TARGET_COMPILER_FLAG} ${HEADER_EXISTS_FLAGS})
            
            target_link_libraries(${PROJECT_NAME}_${APP_CONFIG} PRIVATE ${DEPS_TO_LINK})
            target_link_options(${PROJECT_NAME}_${APP_CONFIG} PRIVATE ${APP_TARGET_COMPILER_FLAG} ${HEADER_EXISTS_FLAGS})

            message(STATUS ${APP_CONFIG})
            message(STATUS ${APP_COMPILER_FLAGS_${APP_CONFIG}}) 

            # Setup build output
            file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/")
            set_target_properties(${PROJECT_NAME}_${APP_CONFIG} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/${APP_CONFIG}")
        endif()
   
        add_app_file_flags() 
   
    endforeach()
endfunction()

## Registers a module and it's dependencies
function(XMOS_REGISTER_MODULE)
    if(ARGC GREATER 0)
        ## Do not output added library message
        string(FIND ${ARGV0} "silent" ${LIB_NAME}_SILENT_FLAG)
        if(${LIB_NAME}_SILENT_FLAG GREATER -1)
            set(${LIB_NAME}_SILENT_FLAG True)
        endif()
    endif()

    set(DEP_MODULE_LIST "")
    if(NOT TARGET ${LIB_NAME})
        if(NOT ${LIB_NAME}_SILENT_FLAG)
            add_library(${LIB_NAME} STATIC)
            set_property(TARGET ${LIB_NAME} PROPERTY VERSION ${LIB_VERSION})
        else()
            add_library(${LIB_NAME} OBJECT EXCLUDE_FROM_ALL)
            set_property(TARGET ${LIB_NAME} PROPERTY VERSION ${LIB_VERSION})
        endif()

        set(DEP_OPTIONAL_HEADERS "")
        set(DEP_FILE_FLAGS "")
        foreach(DEP_MODULE ${LIB_DEPENDENT_MODULES})
            string(REGEX MATCH "^[A-Za-z0-9_ -]+" DEP_NAME ${DEP_MODULE})
            string(REGEX REPLACE "^[A-Za-z0-9_ -]+" "" DEP_FULL_REQ ${DEP_MODULE})

            list(APPEND DEP_MODULE_LIST ${DEP_NAME})
            if("${DEP_FULL_REQ}" STREQUAL "")
                message(FATAL_ERROR "Missing dependency version requirement for ${DEP_NAME} in ${LIB_NAME}.\nA version requirement must be specified for all dependencies.")
            endif()

            string(REGEX MATCH "[0-9.]+" VERSION_REQ ${DEP_FULL_REQ} )
            string(REGEX MATCH "[<>=]+" VERSION_QUAL_REQ ${DEP_FULL_REQ} )

            # Add dependencies directories
            if(NOT TARGET ${DEP_NAME})
                if(EXISTS ${XMOS_APP_MODULES_ROOT_DIR}/${DEP_NAME})
                    add_subdirectory("${XMOS_APP_MODULES_ROOT_DIR}/${DEP_NAME}"  "${CMAKE_BINARY_DIR}/${DEP_NAME}")
                else()
                    message(FATAL_ERROR "Missing dependency ${DEP_NAME}")
                endif()

                get_target_property(${DEP_NAME}_optinc ${DEP_NAME} OPTIONAL_HEADERS)
                list(APPEND DEP_OPTIONAL_HEADERS ${${DEP_NAME}_optinc})
            endif()

            # Check dependency version
            get_target_property(DEP_VERSION ${DEP_NAME} VERSION)

            if(DEP_VERSION VERSION_EQUAL VERSION_REQ)
                string(FIND ${VERSION_QUAL_REQ} "=" DEP_VERSION_CHECK)
            elseif(DEP_VERSION VERSION_LESS VERSION_REQ)
                string(FIND ${VERSION_QUAL_REQ} "<" DEP_VERSION_CHECK)
            elseif(DEP_VERSION VERSION_GREATER VERSION_REQ)
                string(FIND ${VERSION_QUAL_REQ} ">" DEP_VERSION_CHECK)
            endif()

            if(${DEP_VERSION_CHECK} EQUAL "-1")
                message(WARNING "${LIB_NAME} dependency ${DEP_MODULE} not met.  Found ${DEP_NAME}(${DEP_VERSION}).")
            endif()
        endforeach()

        if(NOT ${LIB_NAME}_SILENT_FLAG)
            get_property(XMOS_TARGETS_LIST GLOBAL PROPERTY XMOS_TARGETS_LIST)
            set_property(GLOBAL PROPERTY XMOS_TARGETS_LIST "${XMOS_TARGETS_LIST};${LIB_NAME}")
        endif()

        ## Set optional headers
        if(${LIB_NAME}_DEPS_ONLY_FLAG)
            set(LIB_OPTIONAL_HEADERS ${DEP_OPTIONAL_HEADERS})
        else()
            list(APPEND LIB_OPTIONAL_HEADERS ${DEP_OPTIONAL_HEADERS})
        endif()
        list(REMOVE_DUPLICATES LIB_OPTIONAL_HEADERS)
        list(FILTER LIB_OPTIONAL_HEADERS EXCLUDE REGEX "^.+-NOTFOUND$")
        set_property(TARGET ${LIB_NAME} PROPERTY OPTIONAL_HEADERS ${LIB_OPTIONAL_HEADERS})

        if(NOT ${LIB_NAME}_SILENT_FLAG)
            if("${LIB_ADD_COMPILER_FLAGS}" STREQUAL "")
            else()
                foreach(file ${LIB_XC_SRCS})
                    get_filename_component(ABS_PATH ${file} ABSOLUTE)
                    string(REPLACE ";" " " NEW_FLAGS "${LIB_ADD_COMPILER_FLAGS}")
                    set_source_files_properties(${ABS_PATH} PROPERTIES COMPILE_FLAGS ${NEW_FLAGS})
                endforeach()

                foreach(file ${LIB_CXX_SRCS})
                    get_filename_component(ABS_PATH ${file} ABSOLUTE)
                    string(REPLACE ";" " " NEW_FLAGS "${LIB_ADD_COMPILER_FLAGS}")
                    set_source_files_properties(${ABS_PATH} PROPERTIES COMPILE_FLAGS ${NEW_FLAGS})
                endforeach()

                foreach(file ${LIB_C_SRCS})
                    get_filename_component(ABS_PATH ${file} ABSOLUTE)
                    string(REPLACE ";" " " NEW_FLAGS "${LIB_ADD_COMPILER_FLAGS}")
                    set_source_files_properties(${ABS_PATH} PROPERTIES COMPILE_FLAGS ${NEW_FLAGS})
                endforeach()
            endif()
        endif()
        target_sources(${LIB_NAME} PUBLIC ${LIB_XC_SRCS} ${LIB_CXX_SRCS} ${LIB_ASM_SRCS} ${LIB_C_SRCS})
        target_include_directories(${LIB_NAME} PRIVATE ${LIB_INCLUDES})

        if(NOT ${LIB_NAME}_SILENT_FLAG)
            set(DEPS_TO_LINK "")
            foreach(module ${DEP_MODULE_LIST})
                list(APPEND DEPS_TO_LINK "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/lib${module}.a")
                add_dependencies(${LIB_NAME} ${module})
            endforeach()

            target_link_libraries(
                ${LIB_NAME}
                PUBLIC
                    ${DEPS_TO_LINK}
            )
            target_compile_options(${LIB_NAME} PUBLIC ${LIB_ADD_COMPILER_FLAGS})
        endif()

        if(NOT ${LIB_NAME}_SILENT_FLAG)
            message("Added ${LIB_NAME} (${LIB_VERSION})")
        endif()
    endif()
endfunction()
