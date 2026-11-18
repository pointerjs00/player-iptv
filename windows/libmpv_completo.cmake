# libmpv completo (mpv 0.42 + ffmpeg com filtros: bwdif, yadif...) no lugar do libmpv "minimo" do
# media_kit_libs_windows_video (ffmpeg com --disable-filters, sem desentrelacador).
#
# Descarrega (uma vez, fica em build/) o "mpv-dev" x86_64 das builds publicas do shinchiro e verifica
# o SHA-256. Nao se guarda no repositorio (a DLL tem ~120 MB). Ver third_party/libmpv_completo/LEIA-ME.md.
set(LIBMPV_COMPLETO_ARQUIVO "mpv-dev-x86_64-20261111-git-bcde6b93cc.7z")
set(LIBMPV_COMPLETO_URL
  "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/20261111/${LIBMPV_COMPLETO_ARQUIVO}")
set(LIBMPV_COMPLETO_SHA256 "273c079b11ea5575822f972756f4c9a71149a5c10130353abeb8586738938452")
# a DLL extraida (tambem em third_party/libmpv_completo/SHA256.txt e no ferramentas/empacotar.py)
set(LIBMPV_COMPLETO_DLL_SHA256 "88504ee5560942a955405e99dfb5971368e4cf851321f36565bf2a667271db1b")

set(LIBMPV_COMPLETO_PASTA "${CMAKE_BINARY_DIR}/libmpv-completo")
set(LIBMPV_COMPLETO_ZIP "${CMAKE_BINARY_DIR}/${LIBMPV_COMPLETO_ARQUIVO}")
set(LIBMPV_COMPLETO_DLL "${LIBMPV_COMPLETO_PASTA}/libmpv-2.dll")

# uma DLL de outro release (ou estragada) que ficou na pasta de build volta a extrair-se
if(EXISTS "${LIBMPV_COMPLETO_DLL}")
  file(SHA256 "${LIBMPV_COMPLETO_DLL}" _dll)
  if(NOT _dll STREQUAL LIBMPV_COMPLETO_DLL_SHA256)
    message(STATUS "libmpv completo: a DLL em ${LIBMPV_COMPLETO_PASTA} nao e a fixada; extrai-se de novo")
    file(REMOVE "${LIBMPV_COMPLETO_DLL}")
  endif()
endif()
if(NOT EXISTS "${LIBMPV_COMPLETO_DLL}")
  if(NOT EXISTS "${LIBMPV_COMPLETO_ZIP}")
    message(STATUS "A descarregar o libmpv completo: ${LIBMPV_COMPLETO_URL}")
    file(DOWNLOAD "${LIBMPV_COMPLETO_URL}" "${LIBMPV_COMPLETO_ZIP}"
      EXPECTED_HASH SHA256=${LIBMPV_COMPLETO_SHA256} SHOW_PROGRESS)
  else()
    file(SHA256 "${LIBMPV_COMPLETO_ZIP}" _h)
    if(NOT _h STREQUAL LIBMPV_COMPLETO_SHA256)
      file(REMOVE "${LIBMPV_COMPLETO_ZIP}")
      message(FATAL_ERROR "SHA-256 do libmpv completo errado; apagado. Corra o build de novo.")
    endif()
  endif()
  file(MAKE_DIRECTORY "${LIBMPV_COMPLETO_PASTA}")
  file(ARCHIVE_EXTRACT INPUT "${LIBMPV_COMPLETO_ZIP}" DESTINATION "${LIBMPV_COMPLETO_PASTA}")
endif()
if(NOT EXISTS "${LIBMPV_COMPLETO_DLL}")
  message(FATAL_ERROR "libmpv completo: ${LIBMPV_COMPLETO_DLL} nao existe depois de extrair.")
endif()
file(SHA256 "${LIBMPV_COMPLETO_DLL}" _dll)
if(NOT _dll STREQUAL LIBMPV_COMPLETO_DLL_SHA256)
  file(REMOVE "${LIBMPV_COMPLETO_DLL}")
  message(FATAL_ERROR "libmpv completo: SHA-256 da DLL extraida errado; apagada.")
endif()
