add_executable(audio_convert main.c)
target_link_libraries(audio_convert PRIVATE ffmpeg_example ffmpeg_example_common)

if(WIN32)
    target_compile_definitions(audio_convert PRIVATE FFMPEG_EXAMPLE_USE_SHARED)
endif()
