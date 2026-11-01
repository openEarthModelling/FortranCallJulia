# Smoke consumer for FortranCallJulia's two public consumption tiers.
#
#   find_package (default): against an installed prefix
#       cmake -DFCJ_CONSUMER_MODE=find_package -DCMAKE_PREFIX_PATH=<prefix> ..
#   FetchContent: from a git source, like a third-party consumer
#       cmake -DFCJ_CONSUMER_MODE=fetchcontent \
#             -DFCJ_SOURCE_URL=<git url> -DFCJ_SOURCE_TAG=<ref> ..
#
# Both modes consume the same namespaced target, fcj::fcj_middleware.
cmake_minimum_required(VERSION 3.13)
project(fcj_consumer LANGUAGES Fortran C)

if(NOT FCJ_CONSUMER_MODE)
    set(FCJ_CONSUMER_MODE "find_package")
endif()

if(FCJ_CONSUMER_MODE STREQUAL "find_package")
    find_package(FortranCallJulia 0.1 REQUIRED)
    set(FCJ_TARGET fcj::fcj_middleware)
elseif(FCJ_CONSUMER_MODE STREQUAL "fetchcontent")
    include(FetchContent)
    FetchContent_Declare(fcj
        GIT_REPOSITORY "${FCJ_SOURCE_URL}"
        GIT_TAG        "${FCJ_SOURCE_TAG}")
    FetchContent_MakeAvailable(fcj)
    if(NOT TARGET fcj::fcj_middleware)
        message(FATAL_ERROR "fcj::fcj_middleware not defined after FetchContent")
    endif()
    set(FCJ_TARGET fcj::fcj_middleware)
else()
    message(FATAL_ERROR "Unknown FCJ_CONSUMER_MODE: ${FCJ_CONSUMER_MODE}")
endif()

add_executable(fcj_consumer main.f90)
target_link_libraries(fcj_consumer PRIVATE ${FCJ_TARGET})

# Runtime: the bridge locates the FortranBridge Julia package through
# JULIA_FJ_PROJECT or exe-adjacent probing; the smoke driver exports
# JULIA_FJ_PROJECT, so nothing is copied at build time.
