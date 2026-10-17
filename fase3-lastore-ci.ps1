[CmdletBinding()]
param(
    [string]$ProjectRoot = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Captured {
    param([string]$Command, [string]$WorkingDirectory)
    Push-Location -LiteralPath $WorkingDirectory
    try {
        cmd /d /s /c "$Command 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "Falló el comando: $Command (código $LASTEXITCODE)" }
    }
    finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot '.git'))) {
    throw "No se encontró el repositorio LA Store en $ProjectRoot"
}

$mavenCommand = Get-ChildItem -Path "$env:USERPROFILE\.m2\wrapper\dists" -Filter mvn.cmd -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $mavenCommand) {
    $mavenCommand = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source
}
if (-not $mavenCommand) { throw 'No se encontró Maven para ejecutar las pruebas.' }

$pomPath = Join-Path $ProjectRoot 'ms-clientes\pom.xml'
$pomContent = [System.IO.File]::ReadAllText($pomPath)
if ($pomContent -notmatch '<artifactId>h2</artifactId>') {
    $anchor = '        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>'
    $h2Dependency = @'
        <dependency><groupId>com.h2database</groupId><artifactId>h2</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
'@
    if (-not $pomContent.Contains($anchor)) { throw 'No se encontró el punto de inserción esperado en ms-clientes/pom.xml.' }
    $pomContent = $pomContent.Replace($anchor, $h2Dependency.TrimEnd())
    Write-Utf8File $pomPath $pomContent
}

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\test\resources\application.yml') @'
spring:
  datasource:
    url: jdbc:h2:mem:lastore_clientes_test;MODE=MySQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE
    driver-class-name: org.h2.Driver
    username: sa
    password:
  jpa:
    hibernate:
      ddl-auto: create-drop
    open-in-view: false
eureka:
  client:
    enabled: false
'@

Write-Utf8File (Join-Path $ProjectRoot 'ms-clientes\src\test\java\com\lastore\clientes\repository\ClienteRepositoryTest.java') @'
package com.lastore.clientes.repository;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase.Replace;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import com.lastore.clientes.model.Cliente;

@DataJpaTest
@AutoConfigureTestDatabase(replace = Replace.NONE)
class ClienteRepositoryTest {
    @Autowired
    private ClienteRepository clienteRepository;

    @Test
    void testInsertarCliente() {
        Cliente cliente = new Cliente(null, "70000001", "Cliente Insertado", "900000001", "insertado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);

        assertThat(guardado.getId()).isNotNull();
    }

    @Test
    void testActualizarCliente() {
        Cliente cliente = new Cliente(null, "70000002", "Cliente Actualizado", "900000002", "actualizado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);
        guardado.setTelefono("999888777");
        clienteRepository.saveAndFlush(guardado);

        Cliente actualizado = clienteRepository.findById(guardado.getId()).orElseThrow();
        assertThat(actualizado.getTelefono()).isEqualTo("999888777");
    }

    @Test
    void testListarClientes() {
        clienteRepository.saveAndFlush(new Cliente(null, "70000003", "Cliente Lista Uno", "900000003", "lista1@lastore.pe"));
        clienteRepository.saveAndFlush(new Cliente(null, "70000004", "Cliente Lista Dos", "900000004", "lista2@lastore.pe"));

        List<Cliente> clientes = clienteRepository.findAll();
        assertThat(clientes).hasSizeGreaterThanOrEqualTo(2);
    }

    @Test
    void testEliminarCliente() {
        Cliente cliente = new Cliente(null, "70000005", "Cliente Eliminado", "900000005", "eliminado@lastore.pe");
        Cliente guardado = clienteRepository.saveAndFlush(cliente);
        clienteRepository.deleteById(guardado.getId());
        clienteRepository.flush();

        assertThat(clienteRepository.findById(guardado.getId())).isEmpty();
    }
}
'@

Write-Utf8File (Join-Path $ProjectRoot '.github\workflows\ci.yml') @'
name: LA Store CI

on:
  push:
    branches:
      - main
  pull_request:
    branches:
      - main

jobs:
  build-and-test:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
          cache: maven

      - name: Build and Test Microservices
        run: |
          mvn -B clean test -f ms-eureka-server/pom.xml
          mvn -B clean test -f ms-api-gateway/pom.xml
          mvn -B clean test -f ms-auth/pom.xml
          mvn -B clean test -f ms-clientes/pom.xml
          mvn -B clean test -f ms-reparaciones/pom.xml
          mvn -B clean test -f ms-pagos/pom.xml
'@

$thisScript = $MyInvocation.MyCommand.Path
$destinationScript = Join-Path $ProjectRoot 'fase3-lastore-ci.ps1'
if ($thisScript -and ([System.IO.Path]::GetFullPath($thisScript) -ne [System.IO.Path]::GetFullPath($destinationScript))) {
    Copy-Item -LiteralPath $thisScript -Destination $destinationScript -Force
}

Write-Host "`n=== Ejecutando pruebas de ms-clientes ===" -ForegroundColor Cyan
Invoke-Captured ('"' + $mavenCommand + '" test') (Join-Path $ProjectRoot 'ms-clientes')

Invoke-Captured 'git add .' $ProjectRoot
$stagedOutput = cmd /d /s /c "git -C `"$ProjectRoot`" diff --cached --quiet 2>&1"
if ($LASTEXITCODE -ne 0) {
    Invoke-Captured 'git commit -m "feat(fase3): add data access JUnit tests and GitHub Actions CI workflow"' $ProjectRoot
}

Invoke-Captured 'git branch -M main' $ProjectRoot

$originOutput = cmd /d /s /c "git -C `"$ProjectRoot`" remote get-url origin 2>&1"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($originOutput -join ''))) {
    throw 'Pruebas y commit completados, pero no existe el remoto origin. Configure origin y vuelva a ejecutar el script para realizar git push -u origin main.'
}

Invoke-Captured 'git push -u origin main' $ProjectRoot
Write-Host "`nFASE 3 COMPLETADA: pruebas aprobadas y push enviado a origin/main." -ForegroundColor Green
