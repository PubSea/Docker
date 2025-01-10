@echo off

for /f "delims=[] tokens=2" %%a in ('ping -4 -n 1 %ComputerName% ^| findstr [') do set networkIp=%%a
echo Network IP: %networkIp%

docker-compose up -d
 
timeout  /t 10 /nobreak 
 
docker exec -it mongo.one.db mongosh --eval "rs.initiate({_id:'dbrs', members: [{_id:0, host: '%networkIp%:27018'},{_id:1, host: '%networkIp%:27019'},{_id:2, host: '%networkIp%:27020'}]})"

timeout  /t 1000 /nobreak