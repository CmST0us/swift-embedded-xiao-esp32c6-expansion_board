# Register the app as an IDF component
idf_component_register(
    SRCS /dev/null # We don't have any C++ sources
    PRIV_INCLUDE_DIRS "."
)

idf_build_get_property(target IDF_TARGET)
idf_build_get_property(arch IDF_TARGET_ARCH)

if("${arch}" STREQUAL "xtensa")
    message(FATAL_ERROR "Not supported target: ${target}")
endif()

# Extract the -march flag and remove any vendor-specific extensions (_x*)
string(REGEX MATCH "-march=[^ ]+" march_flag "${CMAKE_C_FLAGS}")
string(REGEX REPLACE "_x[^ ]*" "" march_flag "${march_flag}")

# Extract the -mabi flag or set a default value if not present
string(REGEX MATCH "-mabi=[^ ]+" mabi_flag "${CMAKE_C_FLAGS}")
if("${mabi_flag}" STREQUAL "")
    set(mabi_flag "-mabi=ilp32")
endif()

# Clear the default COMPILE_OPTIONS which include a lot of C/C++ specific compiler flags that the Swift compiler will not accept
get_target_property(var ${COMPONENT_LIB} COMPILE_OPTIONS)
set_target_properties(${COMPONENT_LIB} PROPERTIES COMPILE_OPTIONS "")

# Compute -Xcc flags to set up the C and C++ header search paths for Swift (for bridging header).
set(SWIFT_INCLUDES)
set(SWIFT_INCLUDES_LIST)
foreach(dir ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-Xcc ")
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-I${dir} ")
    list(APPEND SWIFT_INCLUDES_LIST "-Xcc" "-I${dir}")
endforeach()
foreach(dir ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-Xcc ")
    string(CONCAT SWIFT_INCLUDES ${SWIFT_INCLUDES} "-I${dir} ")
    list(APPEND SWIFT_INCLUDES_LIST "-Xcc" "-I${dir}")
endforeach()

# Swift compiler flags to build in Embedded Swift mode, optimize for size, choose the right ISA, ABI, etc.
target_compile_options(${COMPONENT_LIB} PUBLIC "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
        -target riscv32-none-none-eabi
        -Xfrontend -function-sections -enable-experimental-feature Embedded -wmo -parse-as-library -Osize
        -Xcc ${march_flag} -Xcc ${mabi_flag} -Xcc -fno-pic -Xcc -fno-pie
        
        -pch-output-dir /tmp
        -Xfrontend -enable-single-module-llvm-emission
        
        -Xlinker -lgcc -Xlinker -lm
        
        ${SWIFT_INCLUDES}

        -import-bridging-header ${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h
    >")

# Enable Swift support in CMake, force Whole Module builds (required by Embedded Swift), and use "CMAKE_Swift_COMPILER_WORKS" to
# skip the trial compilations which don't (yet) correctly work when cross-compiling.
set(CMAKE_Swift_COMPILER_WORKS YES)
set(CMAKE_Swift_COMPILATION_MODE_DEFAULT wholemodule)
set(CMAKE_Swift_COMPILATION_MODE wholemodule)
enable_language(Swift)

# ======================Package Support======================
# Add Package Support
# The target swift will be building for
set(SWIFT_TARGET "riscv32-none-none-eabi")
# The target of the host OS, required for sourcekitLSP to work
set(SWIFT_LSP_TARGET "x86_64-unknown-linux-gnu")
# Name of the library product in Package.swift
set(SWIFT_PRODUCT_NAME "App")

# Define output file of swift package
set(SWIFT_PRODUCT_BUILD   "${COMPONENT_DIR}/.build")
set(SWIFT_PRODUCT_RELEASE "${SWIFT_PRODUCT_BUILD}/release")
set(SWIFT_PRODUCT_ARCHIVE "${SWIFT_PRODUCT_RELEASE}/lib${SWIFT_PRODUCT_NAME}.a")

# Get swift toolchain location
execute_process(COMMAND which swift OUTPUT_VARIABLE _SWIFT_LOCATION OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND realpath ${_SWIFT_LOCATION} OUTPUT_VARIABLE _SWIFT_ABS_LOCATION OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND dirname ${_SWIFT_ABS_LOCATION} OUTPUT_VARIABLE SWIFT_TOOLCHAIN OUTPUT_STRIP_TRAILING_WHITESPACE)

# 打印 SWIFT_INCLUDES
message(STATUS "SWIFT_INCLUDES: ${SWIFT_INCLUDES}")

# Change SWIFT_INCLUDES to SWIFT_INCLUDES_LIST
separate_arguments(SWIFT_INCLUDES_LIST UNIX_COMMAND "${SWIFT_INCLUDES}")

# Generate Archive
add_custom_target(swift-archive
	COMMAND
		# Remove the archive. Swift does not overwrite this on building but merges them.
		# If the file with app_main gets renamed, both objectfiles (old and new) will be in the archive, potentially causing problems
		rm -f ${SWIFT_PRODUCT_ARCHIVE}
		&&
		${SWIFT_TOOLCHAIN}/swift package update
			--package-path ${COMPONENT_DIR}	
		&&
		${SWIFT_TOOLCHAIN}/swift build
			-c release
			--package-path ${COMPONENT_DIR}
			
			--triple ${SWIFT_TARGET}
			--traits Embedded
			-Xswiftc -target -Xswiftc riscv32-none-none-eabi
			-Xswiftc -enable-experimental-feature -Xswiftc Embedded
			-Xswiftc -wmo
			-Xswiftc -parse-as-library
			-Xswiftc -Osize
			-Xswiftc -Xfrontend -Xswiftc -function-sections
			-Xswiftc -Xfrontend -Xswiftc -enable-single-module-llvm-emission
			-Xlinker -lgcc
			-Xlinker -lm 

			-Xswiftc -pch-output-dir -Xswiftc /tmp

			-Xcc ${march_flag} 
			-Xcc ${mabi_flag} 
			-Xcc -fno-pic 
			-Xcc -fno-pie
			
			# Get includes for C-std libraries and extra components
			${SWIFT_INCLUDES_LIST}
            $$\( echo '$<TARGET_PROPERTY:__idf_main,INCLUDE_DIRECTORIES>' | tr '\;' '\\n' | sed -e 's/\\\(.*\\\)/-Xcc -I\\1/g' \)
	BYPRODUCTS
		${SWIFT_PRODUCT_ARCHIVE}
)


add_custom_command(
    TARGET swift-archive
    POST_BUILD
    COMMAND ${CMAKE_OBJCOPY} --remove-section .swift_modhash
        ${SWIFT_PRODUCT_ARCHIVE} ${SWIFT_PRODUCT_ARCHIVE}
)

# Generate all necessary include paths for LSP
add_custom_target(swift-compile-flags
	COMMAND
		echo ''
		&&
		\( echo '${SWIFT_INCLUDES}' && \( echo '$<TARGET_PROPERTY:__idf_main,INCLUDE_DIRECTORIES>' | tr '\;' '\\n' | sed -e 's/\\\(.*\\\)/-Xcc -I\\1/g' \) \)
		| tr ' ' '\\n' | grep '^-I' > ${SWIFT_PRODUCT_BUILD}/lsp_compile_flags.txt
	BYPRODUCTS
		${SWIFT_PRODUCT_BUILD}/lsp_compile_flags.txt
)

# Create needed symlinks so LSP finds the module information
add_custom_target(swift-lsp-symlink
	COMMAND
		rm -rf ${SWIFT_PRODUCT_BUILD}/${SWIFT_LSP_TARGET}
		&& ln -sf ${SWIFT_PRODUCT_BUILD}/${SWIFT_TARGET} ${SWIFT_PRODUCT_BUILD}/${SWIFT_LSP_TARGET}
		&& rm -rf ${SWIFT_PRODUCT_BUILD}/${SWIFT_TARGET}/debug
		&& ln -sf ${SWIFT_PRODUCT_BUILD}/${SWIFT_TARGET}/release ${SWIFT_PRODUCT_BUILD}/${SWIFT_TARGET}/debug
	DEPENDS
		swift-archive
)

# Extract Objectfile with app_main() symbol
# So we can append it to __idf_main and not (just) as archive
# This is so the linker will correctly resolve dependencies:
# * of FreeRTOS to app_main()
# * from app_main() to other components
add_custom_command(
	OUTPUT ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o
	COMMAND
		# Extract first .o which defines the 'app_main' symbol
		${SWIFT_TOOLCHAIN}/llvm-ar x ${SWIFT_PRODUCT_ARCHIVE} $$\( nm --defined-only -A ${SWIFT_PRODUCT_ARCHIVE} | grep -m 1 'app_main' | cut -d: -f2 \) --output ${SWIFT_PRODUCT_RELEASE}
		# Rename it to a predicatble file
		&& \( mv -f -T ${SWIFT_PRODUCT_RELEASE}/$$\( nm --defined-only -A ${SWIFT_PRODUCT_ARCHIVE} | grep -m 1 'app_main' | cut -d: -f2 \) ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o 2>/dev/null || \(
			rm -rf ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o && mv -f ${SWIFT_PRODUCT_RELEASE}/$$\( nm --defined-only -A ${SWIFT_PRODUCT_ARCHIVE} | grep -m 1 'app_main' | cut -d: -f2 \) ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o \)
		\)
	DEPENDS 
		swift-archive
		${SWIFT_PRODUCT_ARCHIVE}
		swift-compile-flags
		${SWIFT_PRODUCT_BUILD}/lsp_compile_flags.txt
		swift-lsp-symlink
)
add_custom_target(swift_package_app_main DEPENDS ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o)

target_link_libraries(__idf_main ${SWIFT_PRODUCT_ARCHIVE})
target_link_libraries(__idf_main ${SWIFT_PRODUCT_RELEASE}/_swift_package_app_main.o)

# Add compiler runtime library for builtin functions
target_link_libraries(__idf_main gcc)
# Add math library if needed
target_link_libraries(__idf_main m)
# Add swift_package_app_main to __idf_main
add_dependencies(__idf_main swift_package_app_main)
