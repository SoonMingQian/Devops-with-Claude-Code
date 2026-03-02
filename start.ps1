Write-Host "Starting Minikube..."
minikube start
minikube update-context

Write-Host "Starting Jenkins and registry..."
Set-Location "$PSScriptRoot\jenkins"
docker-compose up -d
Set-Location $PSScriptRoot

Write-Host "Connecting containers to minikube network..."
docker network connect minikube jenkins 2>$null
docker network connect minikube registry 2>$null

Write-Host "Fixing insecure registry..."
Set-Content -Path "$env:TEMP\daemon.json" -Value '{}' -NoNewline -Encoding ascii
docker cp "$env:TEMP\daemon.json" minikube:/etc/docker/daemon.json
docker exec minikube sed -i 's|--insecure-registry 10.96.0.0/12|--insecure-registry 10.96.0.0/12 --insecure-registry 192.168.49.4:5000|' /lib/systemd/system/docker.service
docker exec minikube systemctl daemon-reload
docker exec minikube systemctl restart docker

Write-Host "Waiting for API server to recover..."
Start-Sleep -Seconds 60
minikube status

Write-Host "Applying Kubernetes manifests..."
kubectl apply -f "$PSScriptRoot\k8s"

Write-Host "Done! Jenkins: http://localhost:8080"
