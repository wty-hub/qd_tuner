cmake_minimum_required(VERSION 3.10.2)
project(yin_library)

add_library( # Sets the name of the library.
             yin_library

             # Sets the library as a shared library.
             SHARED

             # Provides a relative path to your source file(s).
             ../yin/yin.c
             ../yin/fft.c )

target_include_directories(yin_library PRIVATE ../yin)

find_library( # Defines the name of the path variable that stores the
              # location of the log library.
              log-lib

              # Specifies the name of the NDK library that
              # you want CMake to locate.
              log )

target_link_libraries( # Specifies the target library.
                       yin_library

                       # Links the target library to the log library
                       # included in the NDK.
                       ${log-lib} )
