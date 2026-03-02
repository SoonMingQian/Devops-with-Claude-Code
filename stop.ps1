Write-Host "Deleting Kubernetes resources..."
kubectl delete -f "$PSScriptRoot\k8s"

Write-Host "Stopping Jenkins and registry..."
Set-Location "$PSScriptRoot\jenkins"
docker-compose down
Set-Location $PSScriptRoot

Write-Host "Stopping Minikube..."
minikube stop

Write-Host "All stopped."
