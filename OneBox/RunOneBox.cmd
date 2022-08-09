@echo off
@rem OneBox deployment script for Windows machine using Docker Desktop.
@rem Deploys Dgraph latest image plus schema, test data, and runs a test query.
@rem
@rem Copyright (C) Erik Mavrinac

setlocal EnableDelayedExpansion

set _CURL_OPTIONS=--retry 10 --retry-delay 1 --retry-connrefused --fail-with-body -s

where docker >nul
if ERRORLEVEL 1 (
    @echo.
    @echo ERROR: Docker command not available, is it installed?
    @echo https://docs.docker.com/desktop/windows/install/
    exit /b 1
)

set DGRAPH_ROOT=%USERPROFILE%\dgraph-OneBox
call docker ps | findstr /c:"dgraph/standalone" >nul
if "%ERRORLEVEL%"=="0" (
    @echo.
    @echo Dgraph standalone container already running.
    goto :PostDeployDgraph
)

@echo.
@echo ***********************************************************************
@echo Upgrading to latest Dgraph OneBox standalone image ^(best effort^).
@echo ***********************************************************************
call docker pull dgraph/dgraph:latest
if not "%ERRORLEVEL%"=="0" echo Warning: Failed docker pull for Dgraph, continuing, errorlevel %ERRORLEVEL%

@echo.
@echo ***********************************************************************
@echo Deleting old Dgraph data.
@echo ***********************************************************************
if exist %DGRAPH_ROOT% rd /s/q %DGRAPH_ROOT%

@echo.
@echo ***********************************************************************
@echo Running Dgraph standlone image in a separate window.
@echo Ctrl+C in that window to stop the image.
@echo ***********************************************************************
start docker run --rm -it -p "8080:8080" -p "9080:9080" -p "8000:8000" -p "8001:20000" -v %DGRAPH_ROOT%:/dgraph "dgraph/standalone"
if not "%ERRORLEVEL%"=="0" echo ERROR: Failed docker run for Dgraph, errorlevel %ERRORLEVEL% && exit /b 1

@echo.
@echo Waiting for Dgraph image to start.
:DgraphStart
call curl "http://localhost:8080/graphql" %_CURL_OPTIONS% | findstr /c:"no query string supplied in request" >nul 2>&1
if ERRORLEVEL 1 echo %ERRORLEVEL% Retrying... && goto :DgraphStart

:PostDeployDgraph

@echo.
@echo ***********************************************************************
@echo Applying latest schema to the OneBox
@echo ***********************************************************************
call :DeployDgraphFile @%~dp0Schema.gql alter
if not "%ERRORLEVEL%"=="0" echo ERROR: Failed applying schema, errorlevel %ERRORLEVEL% && exit /b 1
@echo.

@echo.
@echo ***********************************************************************
@echo Applying test data to the OneBox.
@echo ***********************************************************************
call :DeployDgraphFile @%~dp0SampleData.gql "mutate?commitNow=true"
if not "%ERRORLEVEL%"=="0" echo ERROR: Failed uploading test data, errorlevel %ERRORLEVEL% && exit /b 1
@echo.

@echo.
@echo ***********************************************************************
@echo Running test query using DQL format.
@echo https://dgraph.io/docs/query-language/
@echo ***********************************************************************
call :DeployDgraphFile @%~dp0SampleQuery.dql query dql
if not "%ERRORLEVEL%"=="0" echo ERROR: Failed querying, errorlevel %ERRORLEVEL% && exit /b 1
@echo.


@echo.
@echo ***********************************************************************
@echo Dgraph HTTP API running on http://localhost:8080/
@echo Dgraph gRPC API running on http://localhost:9080/
@echo Dgraph web UX ('Ratel') running on http://localhost:8000/
@echo Dgraph data saving to %DGRAPH_ROOT%
@echo ***********************************************************************
@echo.

exit /b 0

@rem Param 1: Path to .gql file (Dgraph RDF format)
@rem Param 2: API call, e.g. alter
@rem Param 3: rdf or dql format, defaults to rdf
:DeployDgraphFile
setlocal
set _type=%3
if "%_type%"=="" set _type=rdf
call curl "http://localhost:8080/%~2" --data-binary %1 --request POST --header "Content-Type: application/%_type%" %_CURL_OPTIONS%
