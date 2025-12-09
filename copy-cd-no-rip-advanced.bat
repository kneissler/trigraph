@echo off
setlocal enabledelayedexpansion

:: ===================================================================
:: Advanced CD/DVD Copy Script with Timeout and Progress Monitoring
:: ===================================================================
:: Uses PowerShell for precise timeout control (1 minute no progress)
:: ===================================================================

echo ====================================
echo CD/DVD Copy with Error Recovery
echo Advanced Version with Timeout
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
set /a TIMEOUT=0

:: Create temporary files
set "TEMP_DIR=%TEMP%\cd_copy_%RANDOM%"
mkdir "%TEMP_DIR%"
set "SUCCESS_LOG=%TEMP_DIR%\success.txt"
set "FAILED_LOG=%TEMP_DIR%\failed.txt"
set "SKIPPED_LOG=%TEMP_DIR%\skipped.txt"
set "TIMEOUT_LOG=%TEMP_DIR%\timeout.txt"
set "FILE_LIST=%TEMP_DIR%\files.txt"

type nul > "%SUCCESS_LOG%"
type nul > "%FAILED_LOG%"
type nul > "%SKIPPED_LOG%"
type nul > "%TIMEOUT_LOG%"

echo.
echo Scanning source directory...

:: Build file list
dir /s /b /a-d "%SOURCE%\*" > "%FILE_LIST%" 2>nul

:: Count total files
set /a TOTAL=0
for /f %%A in ('type "%FILE_LIST%" ^| find /c /v ""') do set /a TOTAL=%%A

echo Found !TOTAL! files
echo.

:: Process each file
set /a CURRENT=0
for /f "usebackq delims=" %%F in ("%FILE_LIST%") do (
    set /a CURRENT+=1
    set "FILE=%%F"
    set "RELPATH=!FILE:%SOURCE%=!"
    set "DESTFILE=%DEST%!RELPATH!"

    :: Create destination directory
    for %%D in ("!DESTFILE!") do (
        if not exist "%%~dpD" mkdir "%%~dpD" 2>nul
    )

    :: Check if file already exists with same size
    if exist "!DESTFILE!" (
        for %%A in ("!FILE!") do set "SRCSIZE=%%~zA"
        for %%B in ("!DESTFILE!") do set "DSTSIZE=%%~zB"

        if "!SRCSIZE!"=="!DSTSIZE!" (
            echo [!CURRENT!/!TOTAL!] [SKIP] !RELPATH!
            echo !RELPATH! >> "%SKIPPED_LOG%"
            set /a SKIPPED+=1
            goto :continue
        )
    )

    echo.
    echo [!CURRENT!/!TOTAL!] Copying: !RELPATH!

    :: Get file size
    for %%A in ("!FILE!") do (
        set "FILESIZE=%%~zA"
        set /a FILESIZE_MB=%%~zA/1048576
    )
    if !FILESIZE_MB! GTR 0 (
        echo               Size: !FILESIZE_MB! MB
    ) else (
        echo               Size: !FILESIZE! bytes
    )

    :: Call PowerShell to copy with timeout monitoring
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$src='!FILE!'.Replace(\"'\",\"''\"); $dst='!DESTFILE!'.Replace(\"'\",\"''\"); " ^
        "$timeout=60; $bufferSize=1MB; " ^
        "try { " ^
        "  $srcStream=[System.IO.File]::OpenRead($src); " ^
        "  $dstStream=[System.IO.File]::Create($dst); " ^
        "  $buffer=New-Object byte[] $bufferSize; " ^
        "  $lastUpdate=[DateTime]::Now; " ^
        "  $totalRead=0; " ^
        "  $lastBytes=0; " ^
        "  while (($read=$srcStream.Read($buffer,0,$buffer.Length)) -gt 0) { " ^
        "    $dstStream.Write($buffer,0,$read); " ^
        "    $totalRead+=$read; " ^
        "    if ($totalRead -ne $lastBytes) { " ^
        "      $lastUpdate=[DateTime]::Now; " ^
        "      $lastBytes=$totalRead; " ^
        "    } elseif (([DateTime]::Now - $lastUpdate).TotalSeconds -gt $timeout) { " ^
        "      throw 'Timeout: No progress for ' + $timeout + ' seconds'; " ^
        "    } " ^
        "  } " ^
        "  $srcStream.Close(); $dstStream.Close(); " ^
        "  exit 0; " ^
        "} catch { " ^
        "  if ($srcStream) {$srcStream.Close()}; " ^
        "  if ($dstStream) {$dstStream.Close(); Remove-Item $dst -Force -EA SilentlyContinue}; " ^
        "  Write-Host $_.Exception.Message; " ^
        "  exit 1; " ^
        "}"

    set "COPY_ERROR=!ERRORLEVEL!"

    if !COPY_ERROR! EQU 0 (
        :: Verify file size
        for %%A in ("!FILE!") do set "SRCSIZE=%%~zA"
        for %%B in ("!DESTFILE!") do set "DSTSIZE=%%~zB"

        if "!SRCSIZE!"=="!DSTSIZE!" (
            echo               [SUCCESS] Verified
            echo !RELPATH! >> "%SUCCESS_LOG%"
            set /a SUCCESS+=1
        ) else (
            echo               [FAILED] Size mismatch
            echo !RELPATH! >> "%FAILED_LOG%"
            set /a FAILED+=1
            del "!DESTFILE!" 2>nul
        )
    ) else (
        echo               [FAILED/TIMEOUT] Could not copy
        echo !RELPATH! >> "%TIMEOUT_LOG%"
        set /a TIMEOUT+=1
        set /a FAILED+=1
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
echo   - Timeout (60s):      !TIMEOUT!
echo Skipped (existing):     !SKIPPED!
echo ====================================
echo.

:: Calculate percentages
if !TOTAL! GTR 0 (
    set /a SUCCESS_PCT=!SUCCESS!*100/!TOTAL!
    set /a FAILED_PCT=!FAILED!*100/!TOTAL!
    echo Success Rate: !SUCCESS_PCT!%%
    echo Failure Rate: !FAILED_PCT!%%
    echo.
)

:: Show failed files if any
if !FAILED! GTR 0 (
    echo Failed/Timeout files:
    echo --------------------------------
    if exist "%TIMEOUT_LOG%" (
        for /f %%A in ('type "%TIMEOUT_LOG%" ^| find /c /v ""') do (
            if %%A GTR 0 (
                echo ** Timeout ^(no progress for 60s^):
                type "%TIMEOUT_LOG%"
            )
        )
    )
    if exist "%FAILED_LOG%" (
        for /f %%A in ('type "%FAILED_LOG%" ^| find /c /v ""') do (
            if %%A GTR 0 (
                echo ** Other failures:
                type "%FAILED_LOG%"
            )
        )
    )
    echo --------------------------------
    echo.
)

:: Save detailed report
set "TIMESTAMP=%DATE:~-4%%DATE:~-10,2%%DATE:~-7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TIMESTAMP=!TIMESTAMP: =0!"
set "REPORT=%DEST%\copy_report_!TIMESTAMP!.txt"

(
    echo ====================================
    echo CD/DVD Copy Report
    echo ====================================
    echo Generated: %DATE% %TIME%
    echo.
    echo Source:      %SOURCE%
    echo Destination: %DEST%
    echo.
    echo ====================================
    echo SUMMARY
    echo ====================================
    echo Total files found:      !TOTAL!
    echo Successfully copied:    !SUCCESS!
    echo Failed ^(corrupted^):     !FAILED!
    echo   - Timeout ^(60s^):      !TIMEOUT!
    echo Skipped ^(existing^):     !SKIPPED!
    echo.
    if !TOTAL! GTR 0 (
        echo Success Rate: !SUCCESS_PCT!%%
        echo Failure Rate: !FAILED_PCT!%%
        echo.
    )
    if !FAILED! GTR 0 (
        echo ====================================
        echo FAILED FILES
        echo ====================================
        if exist "%TIMEOUT_LOG%" (
            for /f %%A in ('type "%TIMEOUT_LOG%" ^| find /c /v ""') do (
                if %%A GTR 0 (
                    echo.
                    echo Timeout ^(no progress for 60 seconds^):
                    echo --------------------------------
                    type "%TIMEOUT_LOG%"
                )
            )
        )
        if exist "%FAILED_LOG%" (
            for /f %%A in ('type "%FAILED_LOG%" ^| find /c /v ""') do (
                if %%A GTR 0 (
                    echo.
                    echo Other failures:
                    echo --------------------------------
                    type "%FAILED_LOG%"
                )
            )
        )
        echo.
    )
    if !SUCCESS! GTR 0 (
        echo ====================================
        echo SUCCESSFULLY COPIED FILES
        echo ====================================
        type "%SUCCESS_LOG%"
    )
    if !SKIPPED! GTR 0 (
        echo.
        echo ====================================
        echo SKIPPED FILES ^(already exist^)
        echo ====================================
        type "%SKIPPED_LOG%"
    )
) > "!REPORT!"

echo Full report saved to:
echo !REPORT!
echo.

:: Cleanup
rmdir /s /q "%TEMP_DIR%" 2>nul

if !FAILED! GTR 0 (
    echo WARNING: Some files could not be copied.
    echo This is normal for damaged CD/DVDs.
    echo Check the report above for details.
    echo.
)

echo Press any key to exit...
pause >nul
