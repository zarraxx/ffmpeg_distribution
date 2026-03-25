add_executable(media_info main.c)
target_link_libraries(media_info PRIVATE ffmpeg_example ffmpeg_example_common)

if(WIN32)
    target_compile_definitions(media_info PRIVATE FFMPEG_EXAMPLE_USE_SHARED)
endif()
