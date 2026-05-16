# start-viewer.ps1

$preferredPorts = @(8080, 5173, 5174, 8000, 3000)
$webRoot = (Get-Location).Path
$listener = $null
$defaultPage = "index.html"

foreach ($port in $preferredPorts) {
    $url = "http://localhost:$port/"
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($url)

    try {
        $listener.Start()
        break
    }
    catch {
        $listener.Close()
        $listener = $null
    }
}

if (-not $listener -or -not $listener.IsListening) {
    Write-Host "Could not start the local server on any configured port." -ForegroundColor Red
    Write-Host "Tried: $($preferredPorts -join ', ')" -ForegroundColor Yellow
    exit 1
}

$launchUrl = "{0}?v={1}" -f $url, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

Write-Host "Starting OIT Lab local web server at $url" -ForegroundColor Cyan
Write-Host "Serving files from: $webRoot" -ForegroundColor Cyan
Write-Host "Opening: $launchUrl" -ForegroundColor Cyan
Write-Host "OIT Lab: $url" -ForegroundColor DarkCyan
Write-Host "Press Ctrl+C in this terminal to stop the server." -ForegroundColor Yellow

# Start the default web browser and point it to the server
Start-Process $launchUrl

try {
    while ($listener.IsListening) {
        # Wait for a request
        try {
            $contextTask = $listener.GetContextAsync()

            while ($listener.IsListening -and -not $contextTask.Wait(200)) {
                # Let PowerShell process Ctrl+C between short waits.
            }

            if (-not $listener.IsListening) {
                break
            }

            $context = $contextTask.GetAwaiter().GetResult()
        }
        catch [System.Net.HttpListenerException] {
            break
        }
        catch [System.ObjectDisposedException] {
            break
        }

        $response = $context.Response
        $requestPath = $context.Request.Url.LocalPath
        
        # Default to the OIT Lab viewer if the root is requested
        if ($requestPath -eq "/") { $requestPath = "/$defaultPage" }
        
        # Prevent directory traversal attacks
        $safePath = $requestPath.Replace("/", "\").TrimStart("\")
        $filePath = Join-Path $webRoot $safePath

        if (Test-Path $filePath -PathType Leaf) {
            # Assign the correct MIME type so the browser renders 3D/HTML correctly
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            switch ($ext) {
                ".html" { $response.ContentType = "text/html" }
                ".js"   { $response.ContentType = "application/javascript" }
                ".css"  { $response.ContentType = "text/css" }
                ".glb"  { $response.ContentType = "model/gltf-binary" }
                ".gltf" { $response.ContentType = "model/gltf+json" }
                default { $response.ContentType = "application/octet-stream" }
            }

            $response.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            $response.Headers.Add("Pragma", "no-cache")
            $response.Headers.Add("Expires", "0")

            # Send the file
            $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.ContentLength64 = $fileBytes.Length
            $response.StatusCode = 200
            $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
        } else {
            # File not found
            $response.StatusCode = 404
        }
        $response.Close()
    }
}
catch {
    Write-Host "`nServer shutting down..." -ForegroundColor Yellow
}
finally {
    if ($listener) {
        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }

    Write-Host "Server stopped." -ForegroundColor Cyan
}