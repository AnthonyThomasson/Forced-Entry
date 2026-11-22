:; exec bash "$(dirname "$0")/godot_open.sh" "$@"
@echo off
rem Opens the Godot editor (--editor) or plays the game, on the Godot the setup resolver finds. One file for both shells
rem (the Herdr buttons in .herdr/config.yaml run it from zsh on a Mac and from Windows PowerShell): sh runs line 1 and
rem execs godot_open.sh; cmd.exe reads line 1 as a label and runs the lines below, which hand over to godot_open.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0godot_open.ps1" %*
exit /b %errorlevel%
