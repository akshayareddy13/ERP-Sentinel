@echo off
rem Run ERP Sentinel on localhost without Docker or PostgreSQL (local SQLite file). Needs Python 3.10+ and Node 18+.
setlocal
cd /d "%~dp0"
set ROOT=%CD%
where python3.11 >nul 2>nul
if not errorlevel 1 (
  set PY=python3.11
) else (
  where python3.12 >nul 2>nul
  if not errorlevel 1 (
    set PY=python3.12
  ) else (
    where python3.10 >nul 2>nul
    if not errorlevel 1 (
      set PY=python3.10
    ) else (
      where python >nul 2>nul
      if not errorlevel 1 (
        set PY=python
      ) else (
        echo Python 3.10-3.13 is required & exit /b 1
      )
    )
  )
)

where npm >nul 2>nul || (echo Node.js npm is required & exit /b 1)
"%PY%" -c "import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 10) and sys.version_info[:2] < (3, 14) else 1)" >nul 2>nul || (echo ERP Sentinel requires Python 3.10-3.13. Found: && "%PY%" -V && exit /b 1)

cd /d "%ROOT%\backend"
if not exist .venv "%PY%" -m venv .venv
call .venv\Scripts\activate.bat
pip install -q -r requirements.txt
set DATABASE_URL=sqlite:///%ROOT:\=/%/backend/erp_sentinel.db
if "%JWT_SECRET%"=="" set JWT_SECRET=local-dev-secret-change-me-0123456789abcdef
set CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
if not exist erp_sentinel.db (echo Creating demo data... & python seed_database.py)
start "ERP Sentinel API" cmd /c ".venv\Scripts\activate.bat && uvicorn app.main:app --host 127.0.0.1 --port 8000"

cd /d "%ROOT%\frontend"
if not exist node_modules call npm install
set NEXT_PUBLIC_API_URL=http://localhost:8000
echo.
echo ERP Sentinel:  http://localhost:3000   (API docs: http://localhost:8000/docs)
echo Login:  admin / Admin@12345
echo.
call npm run dev
