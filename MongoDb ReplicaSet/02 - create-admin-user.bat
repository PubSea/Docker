@echo off

docker exec -it mongo.one.db mongosh --eval "use admin" --eval "db.createUser({user: 'admin', pwd: 'admin', roles: ['root']})"

timeout  /t 1000 /nobreak