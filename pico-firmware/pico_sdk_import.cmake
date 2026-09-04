# This is a copy of <PICO_SDK_PATH>/external/pico_sdk_import.cmake

if (DEFINED ENV{PICO_SDK_PATH} AND (NOT PICO_SDK_PATH))
    set(PICO_SDK_PATH $ENV{PICO_SDK_PATH})
    message("Using PICO_SDK_PATH from environment: ${PICO_SDK_PATH}")
endif ()

if (DEFINED ENV{PICO_SDK_FETCH_FROM_GIT} AND (NOT PICO_SDK_FETCH_FROM_GIT))
    set(PICO_SDK_FETCH_FROM_GIT $ENV{PICO_SDK_FETCH_FROM_GIT})
    message("Using PICO_SDK_FETCH_FROM_GIT from environment: ${PICO_SDK_FETCH_FROM_GIT}")
endif ()

if (NOT PICO_SDK_PATH)
    if (PICO_SDK_FETCH_FROM_GIT)
        include(FetchContent)
        FetchContent_Declare(
                pico_sdk
                GIT_REPOSITORY https://github.com/raspberrypi/pico-sdk
                GIT_TAG master
        )
        FetchContent_MakeAvailable(pico_sdk)
    else ()
        message(FATAL_ERROR
                "SDK location was not specified. Please set PICO_SDK_PATH or set PICO_SDK_FETCH_FROM_GIT to on to fetch from git."
                )
    endif ()
else ()
    get_filename_component(PICO_SDK_PATH "${PICO_SDK_PATH}" REALPATH BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    if (NOT EXISTS "${PICO_SDK_PATH}")
        message(FATAL_ERROR "Directory '${PICO_SDK_PATH}' not found")
    endif ()
    set(PICO_SDK_PATH "${PICO_SDK_PATH}" CACHE PATH "Path to the Pico SDK" FORCE)
    include("${PICO_SDK_PATH}/pico_sdk_init.cmake")
endif ()
