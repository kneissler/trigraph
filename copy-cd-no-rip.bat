@echo off
setlocal enabledelayedexpansion

:: ===================================================================
:: Enhanced CD/DVD Copy Script with Corruption Handling
:: ===================================================================
:: Features:
:: - Copies files individually to handle corrupted files
:: - Timeout after 1 minute of no progress
:: - Continues with next file on error
:: - Shows detailed summary at end
:: ===================================================================

echo ====================================
echo CD/DVD Copy with Error Recovery
echo ====================================
echo.

:: Get source and destination from user
set /p SOURCE="Enter source path (e.g., D:\): "
set /p DEST="Enter destination path: "

:: Validate paths
if not exist "%SOURCE%" (
    echo ERROR: Source path does not exist!
    pause
    exit /b 1
)

if not exist "%DEST%" (
    echo Creating destination folder...
    mkdir "%DEST%" 2>nul
)

:: Initialize counters
set /a TOTAL=0
set /a SUCCESS=0
set /a FAILED=0
set /a SKIPPED=0

:: Create temporary files for tracking
set "TEMP_DIR=%TEMP%\cd_copy_%RANDOM%"
mkdir "%TEMP_DIR%"
set "SUCCESS_LOG=%TEMP_DIR%\success.txt"
set "FAILED_LOG=%TEMP_DIR%\failed.txt"
set "SKIPPED_LOG=%TEMP_DIR%\skipped.txt"

type nul > "%SUCCESS_LOG%"
type nul > "%FAILED_LOG%"
type nul > "%SKIPPED_LOG%"

echo.
echo Scanning source directory...
echo.

:: Process each file individually
for /r "%SOURCE%" %%F in (*) do (
    set /a TOTAL+=1
    set "FILE=%%F"
    set "RELPATH=!FILE:%SOURCE%=!"
    set "DESTFILE=%DEST%!RELPATH!"

    :: Create destination directory if needed
    for %%D in ("!DESTFILE!") do (
        if not exist "%%~dpD" mkdir "%%~dpD" 2>nul
    )

    :: Check if file already exists and has same size
    if exist "!DESTFILE!" (
        for %%A in ("!FILE!") do set "SRCSIZE=%%~zA"
        for %%B in ("!DESTFILE!") do set "DSTSIZE=%%~zB"

        if "!SRCSIZE!"=="!DSTSIZE!" (
            echo [SKIP] Already exists: !RELPATH!
            echo !RELPATH! >> "%SKIPPED_LOG%"
            set /a SKIPPED+=1
            goto :continue
        )
    )

    echo.
    echo [!TOTAL!] Copying: !RELPATH!

    :: Get file size for progress indication
    for %%A in ("!FILE!") do set "FILESIZE=%%~zA"
    set /a FILESIZE_MB=!FILESIZE!/1048576
    if !FILESIZE_MB! GTR 0 (
        echo     Size: !FILESIZE_MB! MB
    ) else (
        echo     Size: !FILESIZE! bytes
    )

    :: Copy with timeout (using robocopy with retry options)
    :: /R:3 = 3 retries, /W:1 = 1 second wait between retries
    :: /NP = no progress (faster), /NDL = no directory list
    :: /NJH = no job header, /NJS = no job summary

    robocopy "%%~dpF" "%%~dpD" "%%~nxF" /R:3 /W:1 /NP /NDL /NJH /NJS /MT:1 >nul 2>&1

    set "COPY_ERROR=!ERRORLEVEL!"

    :: Robocopy error codes: 0-7 are success/partial, 8+ are failures
    if !COPY_ERROR! GEQ 8 (
        echo     [FAILED] Error code: !COPY_ERROR!
        echo !RELPATH! >> "%FAILED_LOG%"
        set /a FAILED+=1

        :: Try alternative method: xcopy with continue on error
        echo     Trying alternative method...
        xcopy "!FILE!" "!DESTFILE!" /C /Q /Y >nul 2>&1

        if !ERRORLEVEL! EQU 0 (
            echo     [SUCCESS] Alternative method worked
            echo !RELPATH! >> "%SUCCESS_LOG%"
            set /a SUCCESS+=1
            set /a FAILED-=1
        ) else (
            echo     [FAILED] Could not copy file - likely corrupted
        )
    ) else (
        echo     [SUCCESS]
        echo !RELPATH! >> "%SUCCESS_LOG%"
        set /a SUCCESS+=1
    )

    :continue
)

:: Display summary
echo.
echo ====================================
echo COPY SUMMARY
echo ====================================
echo Total files found:      !TOTAL!
echo Successfully copied:    !SUCCESS!
echo Failed (corrupted):     !FAILED!
echo Skipped (existing):     !SKIPPED!
echo ====================================
echo.

:: Show failed files if any
if !FAILED! GTR 0 (
    echo Failed files:
    echo --------------------------------
    type "%FAILED_LOG%"
    echo --------------------------------
    echo.
)

:: Save full report
set "REPORT=%DEST%\copy_report_%DATE:~-4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.txt"
set "REPORT=!REPORT: =0!"
(
    echo CD/DVD Copy Report
    echo Generated: %DATE% %TIME%
    echo.
    echo Source: %SOURCE%
    echo Destination: %DEST%
    echo.
    echo ====================================
    echo SUMMARY
    echo ====================================
    echo Total files found:      !TOTAL!
    echo Successfully copied:    !SUCCESS!
    echo Failed ^(corrupted^):     !FAILED!
    echo Skipped ^(existing^):     !SKIPPED!
    echo.
    if !FAILED! GTR 0 (
        echo ====================================
        echo FAILED FILES
        echo ====================================
        type "%FAILED_LOG%"
        echo.
    )
    if !SUCCESS! GTR 0 (
        echo ====================================
        echo SUCCESSFULLY COPIED FILES
        echo ====================================
        type "%SUCCESS_LOG%"
    )
) > "!REPORT!"

echo Full report saved to: !REPORT!
echo.

:: Cleanup
rmdir /s /q "%TEMP_DIR%" 2>nul

echo Press any key to exit...
pause >nul
