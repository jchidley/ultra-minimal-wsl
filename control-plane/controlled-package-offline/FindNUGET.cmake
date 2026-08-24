# Fail-closed NuGet module for the pinned controlled WSL package build.
# It mirrors the source module's package-variable functions but replaces every
# network edge with the verified local cache supplied by the build procedure.

function(find_nuget_package name var_name path)
    string(JSON "${var_name}_VERSION" GET ${NUGET_PACKAGES_JSON} "${name}")

    set(${var_name}_SOURCE_DIR "${CMAKE_BINARY_DIR}/packages/${name}.${${var_name}_VERSION}${path}" PARENT_SCOPE)
    set(${var_name}_VERSION "${${var_name}_VERSION}" PARENT_SCOPE)
endfunction()

function(restore_nuget_packages)
    if(NOT CONTROLLED_NUGET_CACHE OR NOT EXISTS "${CONTROLLED_NUGET_CACHE}/nuget.exe")
        message(FATAL_ERROR "CONTROLLED_NUGET_CACHE must contain the verified nuget.exe")
    endif()

    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/_deps")
    file(COPY_FILE
        "${CONTROLLED_NUGET_CACHE}/nuget.exe"
        "${CMAKE_BINARY_DIR}/_deps/nuget.exe"
        ONLY_IF_DIFFERENT)

    file(TO_CMAKE_PATH "${CONTROLLED_NUGET_CACHE}" CONTROLLED_NUGET_SOURCE)
    set(CONTROLLED_NUGET_CONFIG "${CMAKE_BINARY_DIR}/_deps/controlled-nuget.config")
    file(WRITE "${CONTROLLED_NUGET_CONFIG}"
        "<configuration>\n"
        "  <packageSources><clear/><add key=\"controlled\" value=\"${CONTROLLED_NUGET_SOURCE}\" /></packageSources>\n"
        "  <disabledPackageSources><clear/></disabledPackageSources>\n"
        "  <packageRestore><add key=\"enabled\" value=\"True\" /><add key=\"automatic\" value=\"False\" /></packageRestore>\n"
        "</configuration>\n")

    execute_process(COMMAND
        "${CMAKE_BINARY_DIR}/_deps/nuget.exe"
        restore packages.config
        -SolutionDirectory "${CMAKE_BINARY_DIR}"
        -ConfigFile "${CONTROLLED_NUGET_CONFIG}"
        -NoCache
        -NonInteractive
        -DisableParallelProcessing
        WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
        COMMAND_ERROR_IS_FATAL ANY)
endfunction()

function(parse_nuget_packages_versions)
    set(CMD "$packages=@{}; (Select-Xml -path '${CMAKE_SOURCE_DIR}/packages.config' /packages).Node.ChildNodes | Where-Object { $_.name -ne '#whitespace'} | % {$packages.add($_.id, $_.Attributes['version'].Value) }; $packages | ConvertTo-Json | Write-Host")

    execute_process(
        COMMAND pwsh.exe -NoLogo -NoProfile -NonInteractive -Command "${CMD}"
        OUTPUT_VARIABLE output
        COMMAND_ERROR_IS_FATAL ANY)

    set(NUGET_PACKAGES_JSON ${output} PARENT_SCOPE)
endfunction()
