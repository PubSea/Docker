@echo off

docker exec -it mongo.one.db mongosh --eval "rs.status()"

timeout  /t 1000 /nobreak