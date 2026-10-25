cmake_minimum_required(VERSION 3.22)
project(LumiShow VERSION 0.1.0 LANGUAGES C CXX OBJCXX)

include(FetchContent)
FetchContent_Declare(juce
    GIT_REPOSITORY https://github.com/juce-framework/JUCE.git
    GIT_TAG 9.0.4
    GIT_SHALLOW TRUE)
FetchContent_Declare(roli_blocks_basics
    GIT_REPOSITORY https://github.com/WeAreROLI/roli_blocks_basics.git
    GIT_TAG 212ba4e237638b9ae8c2a4f76dd2070110392031
    SOURCE_DIR ${CMAKE_BINARY_DIR}/modules/roli_blocks_basics)
# roli_blocks_basics has no top-level CMakeLists.txt, so this only downloads it.
FetchContent_MakeAvailable(juce roli_blocks_basics)

juce_add_module(${roli_blocks_basics_SOURCE_DIR})
juce_add_console_app(LumiShow)
target_sources(LumiShow PRIVATE main.mm)
target_compile_definitions(LumiShow PRIVATE JUCE_USE_CURL=0 JUCE_WEB_BROWSER=0)
target_link_libraries(LumiShow PRIVATE roli_blocks_basics juce::juce_recommended_config_flags)
