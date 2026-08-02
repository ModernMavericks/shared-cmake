# MavericksDecisions.cmake -- forced explicit decisions (no silent defaults for
# decisions that matter). Currently: the app icon. include()d by Mavericks.cmake.

# mavericks_require_icon(TARGET <t> [ICNS <path>] [ALLOW_GENERIC])
#   Gate + wiring for a bundle's app icon. Exactly one of:
#     * ICNS <path> that EXISTS  -> bundle it (MACOSX_BUNDLE_ICON_FILE) -- the real icon.
#     * ALLOW_GENERIC (or -DMAVERICKS_ALLOW_GENERIC_ICON=ON) -> ship generic ON PURPOSE.
#     * neither -> FATAL_ERROR: you must decide.
#   ICNS given but missing (e.g. container-extraction failed) is also FATAL -- never
#   silently iconless.
function(mavericks_require_icon)
  cmake_parse_arguments(MRI "ALLOW_GENERIC" "TARGET;ICNS" "" ${ARGN})
  if(NOT MRI_TARGET)
    message(FATAL_ERROR "mavericks_require_icon: TARGET is required")
  endif()
  if(MRI_ICNS)
    if(NOT EXISTS "${MRI_ICNS}")
      message(FATAL_ERROR
        "mavericks_require_icon(${MRI_TARGET}): declared icon '${MRI_ICNS}' does not exist "
        "-- it wasn't produced (e.g. the source container was down and extraction failed). "
        "Bring the source up and re-configure, or set -DMAVERICKS_ALLOW_GENERIC_ICON=ON to "
        "ship the generic icon on purpose. Refusing to build ${MRI_TARGET} with no/wrong icon.")
    endif()
    get_filename_component(_mri_name "${MRI_ICNS}" NAME)
    set_source_files_properties("${MRI_ICNS}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_sources(${MRI_TARGET} PRIVATE "${MRI_ICNS}")
    set_target_properties(${MRI_TARGET} PROPERTIES MACOSX_BUNDLE_ICON_FILE "${_mri_name}")
    message(STATUS "Mavericks: ${MRI_TARGET} ships app icon ${_mri_name}")
    return()
  endif()
  if(MRI_ALLOW_GENERIC OR MAVERICKS_ALLOW_GENERIC_ICON)
    message(STATUS "Mavericks: ${MRI_TARGET} ships the GENERIC icon by explicit opt-in")
    return()
  endif()
  message(FATAL_ERROR
    "mavericks_require_icon(${MRI_TARGET}): no icon decided. Provide ICNS <path/to.icns>, "
    "or opt into generic with ALLOW_GENERIC (or -DMAVERICKS_ALLOW_GENERIC_ICON=ON). "
    "ModernMavericks apps must make an explicit icon decision.")
endfunction()
