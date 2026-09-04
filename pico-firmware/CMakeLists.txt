cmake_minimum_required(VERSION 3.13)

# Initialize Pico SDK
include(pico_sdk_import.cmake)

project(pico_location_spoofer C CXX ASM)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

pico_sdk_init()

add_executable(pico_location_spoofer
    main.c
    usb_descriptors.c
)

# Pull in Raspberry Pi Pico SDK and TinyUSB libraries
target_include_directories(pico_location_spoofer PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}
)

target_link_libraries(pico_location_spoofer
    pico_stdlib
    hardware_uart
    hardware_timer
    tinyusb_device
    tinyusb_board
)

# Enable USB CDC output, disable standard UART stdio (UART used for NMEA GPS emulation)
pico_enable_stdio_usb(pico_location_spoofer 1)
pico_enable_stdio_uart(pico_location_spoofer 0)

# Generate UF2 binary for drag-and-drop BOOTSEL flashing
pico_add_extra_outputs(pico_location_spoofer)
