$ErrorActionPreference = 'Stop'
$project = 'C:\Users\Luis\Desktop\6to ciclo\DAW 2\Proyecto-LAStore'
$exchange = 'ex.lastore.eventos'

function Write-Utf8File([string]$Path, [string]$Content) {
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}
function Replace-Exact([string]$Path, [string]$Old, [string]$New) {
    $content = [System.IO.File]::ReadAllText($Path)
    if (-not $content.Contains($Old)) {
        if ($content.Contains($New)) { return }
        throw "No se encontro el patron esperado en $Path`: $Old"
    }
    Write-Utf8File $Path ($content.Replace($Old, $New))
}
function Write-RabbitConfig([string]$Module, [string]$Package) {
    $path = Join-Path $project "$Module\src\main\java\com\lastore\$Package\config\RabbitMQConfig.java"
    $content = @'
package com.lastore.__PACKAGE__.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.beans.factory.annotation.Qualifier;

@Configuration
public class RabbitMQConfig {
    public static final String EXCHANGE = "ex.lastore.eventos";
    public static final String APROBADA = "q.lastore.cotizacion.aprobada";
    public static final String CANCELADA = "q.lastore.cotizacion.cancelada";
    public static final String PAGO_ANULADO = "q.lastore.pago.anulado";
    public static final String RK_APROBADA = "rk.cotizacion.aprobada";
    public static final String RK_CANCELADA = "rk.cotizacion.cancelada";
    public static final String RK_PAGO_ANULADO = "rk.pago.anulado";

    @Bean public Queue cotizacionAprobada() { return new Queue(APROBADA, true); }
    @Bean public Queue cotizacionCancelada() { return new Queue(CANCELADA, true); }
    @Bean public Queue pagoAnulado() { return new Queue(PAGO_ANULADO, true); }
    @Bean public DirectExchange eventosExchange() { return new DirectExchange(EXCHANGE, true, false); }

    @Bean public Binding aprobadaBinding(@Qualifier("cotizacionAprobada") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_APROBADA);
    }
    @Bean public Binding canceladaBinding(@Qualifier("cotizacionCancelada") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_CANCELADA);
    }
    @Bean public Binding pagoAnuladoBinding(@Qualifier("pagoAnulado") Queue queue, DirectExchange eventosExchange) {
        return BindingBuilder.bind(queue).to(eventosExchange).with(RK_PAGO_ANULADO);
    }
}
'@
    Write-Utf8File $path ($content.Replace('__PACKAGE__', $Package))
}
function Invoke-Native([string]$Executable, [string[]]$Arguments, [string]$Directory) {
    Push-Location $Directory
    try {
        & $Executable @Arguments 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "$Executable fallo con codigo $LASTEXITCODE" }
    } finally { Pop-Location }
}

if (-not (Test-Path -LiteralPath (Join-Path $project '.git'))) { throw 'Repositorio no encontrado' }
$source = $MyInvocation.MyCommand.Path
$destination = Join-Path $project 'fix-rabbitmq-topology.ps1'
if ($source -ne $destination) { Copy-Item -LiteralPath $source -Destination $destination -Force }

# Windows bloquea los JAR en ejecucion durante mvn clean; detener solo procesos Java verificados.
foreach ($item in @(@{ Port = 8083; Name = 'ms-reparaciones' }, @{ Port = 8084; Name = 'ms-pagos' })) {
    $connections = Get-NetTCPConnection -LocalPort $item.Port -State Listen -ErrorAction SilentlyContinue
    foreach ($connection in $connections) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$($connection.OwningProcess)"
        if ($process.Name -notin @('java.exe','javaw.exe') -or $process.CommandLine -notlike "*$($item.Name)*") {
            throw "Puerto $($item.Port) ocupado por proceso no reconocido; no se detiene"
        }
        Stop-Process -Id $connection.OwningProcess -Force
    }
}

Write-RabbitConfig 'ms-reparaciones' 'reparaciones'
Write-RabbitConfig 'ms-pagos' 'pagos'
$ticketService = Join-Path $project 'ms-reparaciones\src\main\java\com\lastore\reparaciones\service\TicketStateService.java'
$pagoService = Join-Path $project 'ms-pagos\src\main\java\com\lastore\pagos\service\PagoStateService.java'
$ticketTest = Join-Path $project 'ms-reparaciones\src\test\java\com\lastore\reparaciones\service\TicketStateServiceTest.java'
$pagoTest = Join-Path $project 'ms-pagos\src\test\java\com\lastore\pagos\service\PagoStateServiceTest.java'
foreach ($path in @($ticketService, $ticketTest)) {
    Replace-Exact $path 'convertAndSend(RabbitMQConfig.APROBADA,' 'convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_APROBADA,'
    Replace-Exact $path 'convertAndSend(RabbitMQConfig.CANCELADA,' 'convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_CANCELADA,'
}
foreach ($path in @($pagoService, $pagoTest)) {
    Replace-Exact $path 'convertAndSend(RabbitMQConfig.PAGO_ANULADO,' 'convertAndSend(RabbitMQConfig.EXCHANGE, RabbitMQConfig.RK_PAGO_ANULADO,'
}

# Eliminar solamente una declaracion MySQL duplicada preexistente que impide leer el POM.
foreach ($module in @('ms-reparaciones','ms-pagos')) {
    $pom = Join-Path $project "$module\pom.xml"
    $pomContent = [System.IO.File]::ReadAllText($pom)
    $mysqlDeclaration = '<dependency><groupId>com.mysql</groupId><artifactId>mysql-connector-j</artifactId><scope>runtime</scope></dependency>'
    if (($pomContent.Split(@($mysqlDeclaration), [System.StringSplitOptions]::None).Length - 1) -eq 2) {
        $pomContent = [regex]::Replace($pomContent, "(?m)^[ \t]*$([regex]::Escape($mysqlDeclaration))\r?\n", '', 1)
        Write-Utf8File $pom $pomContent
    }
}

$maven = (Get-Command mvn.cmd -ErrorAction SilentlyContinue).Source
if (-not $maven) {
    $maven = Get-ChildItem -Path (Join-Path $env:USERPROFILE '.m2\wrapper\dists') -Filter mvn.cmd -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $maven) { throw 'Maven no encontrado' }
foreach ($module in @('ms-reparaciones','ms-pagos')) {
    $directory = Join-Path $project $module
    Invoke-Native $maven @('clean','install','-DskipTests') $directory
    Invoke-Native $maven @('test','-Dnet.bytebuddy.experimental=true') $directory
}

$runtime = Join-Path $project '.runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
foreach ($item in @(@{ Port = 8083; Name = 'ms-reparaciones' }, @{ Port = 8084; Name = 'ms-pagos' })) {
    $jar = Join-Path $project "$($item.Name)\target\$($item.Name)-0.0.1-SNAPSHOT.jar"
    if (-not (Test-Path -LiteralPath $jar)) {
        $jar = Get-ChildItem -LiteralPath (Join-Path $project "$($item.Name)\target") -Filter '*.jar' | Where-Object Name -NotLike '*.original' | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $jar) { throw "JAR no encontrado para $($item.Name)" }
    Start-Process -FilePath 'java.exe' -ArgumentList @('-jar', ('"' + $jar + '"')) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $runtime "$($item.Name).out.log") -RedirectStandardError (Join-Path $runtime "$($item.Name).err.log")
}
foreach ($port in @(8083,8084)) {
    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$port/api/v1/$(@{8083='tickets';8084='pagos'}[$port])" -UseBasicParsing -TimeoutSec 2
            if ($response.StatusCode -eq 200) { $ready = $true; break }
        } catch { Start-Sleep -Seconds 2 }
    }
    if (-not $ready) { throw "Servicio en puerto $port no respondio HTTP 200" }
}

Invoke-Native 'git.exe' @('add','--','fix-rabbitmq-topology.ps1','ms-reparaciones/src/main/java/com/lastore/reparaciones/config/RabbitMQConfig.java','ms-reparaciones/src/main/java/com/lastore/reparaciones/service/TicketStateService.java','ms-reparaciones/src/test/java/com/lastore/reparaciones/service/TicketStateServiceTest.java','ms-pagos/src/main/java/com/lastore/pagos/config/RabbitMQConfig.java','ms-pagos/src/main/java/com/lastore/pagos/service/PagoStateService.java','ms-pagos/src/test/java/com/lastore/pagos/service/PagoStateServiceTest.java') $project
Invoke-Native 'git.exe' @('commit','-m','refactor(rabbitmq): implement full AMQP topology with direct exchange, bindings and routing keys') $project
Invoke-Native 'git.exe' @('status','--short') $project
