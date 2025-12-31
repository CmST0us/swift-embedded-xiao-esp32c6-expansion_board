#
# Patch ESP-IDF generated linker script `sections.ld` to keep `.got` / `.got.plt`.
#
# ESP-IDF 5.5.x `sections.ld` ends with:
#   /DISCARD/ : { *(.rela.*) *(.got .got.plt) ... }
#
# Embedded Swift (and some toolchains) can require `.got/.got.plt` to exist, so
# discarding them breaks the final link with:
#   ld: discarded output section: `.got.plt'
#
# This script injects explicit output sections for `.got` and `.got.plt` right
# before the `/DISCARD/` block so they are consumed earlier and not discarded.
#

if(NOT DEFINED SECTIONS_LD)
    message(FATAL_ERROR "SECTIONS_LD is not set")
endif()

if(NOT EXISTS "${SECTIONS_LD}")
    # During some configure/build sequences the file may not exist yet.
    # Don't fail the whole build; the patch target can run again later.
    message(STATUS "sections.ld not found yet, skipping patch: ${SECTIONS_LD}")
    return()
endif()

file(READ "${SECTIONS_LD}" _content)

# Idempotency: if already patched, do nothing.
if(_content MATCHES "/\\* swift_got_fix \\*/")
    message(STATUS "sections.ld already patched: ${SECTIONS_LD}")
    return()
endif()

set(_needle "\n  /DISCARD/ :")
string(FIND "${_content}" "${_needle}" _pos)
if(_pos EQUAL -1)
    message(FATAL_ERROR "Could not find /DISCARD/ block in: ${SECTIONS_LD}")
endif()

set(_insertion "\n  /* swift_got_fix */\n  .got :\n  {\n    *(.got)\n    *(.got.*)\n    *(.igot)\n    *(.igot.*)\n  } > sram_seg\n\n  .got.plt :\n  {\n    *(.got.plt)\n    *(.got.plt.*)\n    *(.igot.plt)\n    *(.igot.plt.*)\n  } > sram_seg\n")

string(REPLACE "${_needle}" "${_insertion}${_needle}" _patched "${_content}")

file(WRITE "${SECTIONS_LD}" "${_patched}")
message(STATUS "Patched sections.ld to keep .got/.got.plt: ${SECTIONS_LD}")


