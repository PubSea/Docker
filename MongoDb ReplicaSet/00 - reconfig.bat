@echo off

set /P ip=Enter your ip address retrieved from ipconfig or ifconfig command: 
 
docker exec -it mongo.one.db mongosh --eval "rs.reconfig({_id:'dbrs', members: [{_id:0, host: '%ip%:27018'},{_id:1, host: '%ip%:27019'},{_id:2, host: '%ip%:27020'}]}, {force: true})"

timeout  /t 1000 /nobreak