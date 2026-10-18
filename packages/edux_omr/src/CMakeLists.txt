# EduX javob varaqasi o'quvchisi (Android: Gradle shu faylni NDK bilan yig'adi).
cmake_minimum_required(VERSION 3.10)

project(edux_omr_library VERSION 1.0.0 LANGUAGES C CXX)

add_library(edux_omr SHARED
  edux_omr.cpp
  quirc/quirc.c
  quirc/decode.c
  quirc/identify.c
  quirc/version_db.c
)

set_target_properties(edux_omr PROPERTIES
  PUBLIC_HEADER edux_omr.h
  OUTPUT_NAME "edux_omr"
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
)

target_include_directories(edux_omr PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(edux_omr PUBLIC DART_SHARED_LIB)
# Tezlik muhim: kadr ~5 marta/soniya tahlil qilinadi
target_compile_options(edux_omr PRIVATE -O3 -fvisibility=hidden)

if (ANDROID)
  # Android 15+ (16 KB sahifali qurilmalar) uchun
  target_link_options(edux_omr PRIVATE "-Wl,-z,max-page-size=16384")
endif()
