add_executable(video_convert main.c)
target_link_libraries(video_convert PRIVATE ffmpeg_example ffmpeg_example_common)

if(WIN32)
    target_compile_definitions(video_convert PRIVATE FFMPEG_EXAMPLE_USE_SHARED)
endif()
