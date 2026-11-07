const password = os.getenv('MYSQL_ROOT_PASSWORD');
const connection = host => ({scheme: 'mysql', user: 'root', password, host, port: 3306});
shell.connect(connection('mysql-1'));
let cluster;
const metadataExists = session.runSql("SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='mysql_innodb_cluster_metadata'").fetchOne()[0];
if (metadataExists) {
    // A complete outage needs explicit recovery; never force quorum or discard GTIDs.
    cluster = dba.getCluster('pubsea');
    shell.connect(connection(cluster.status().defaultReplicaSet.primary.split(':')[0]));
    cluster = dba.getCluster('pubsea');
} else {
    cluster = dba.createCluster('pubsea', {gtidSetIsComplete: true, communicationStack: 'MYSQL'});
}
for (const host of ['mysql-2', 'mysql-3']) {
    const topology = cluster.status().defaultReplicaSet.topology;
    if (!topology[host + ':3306']) {
        cluster.addInstance(connection(host), {recoveryMethod: 'clone'});
    }
}
const status = cluster.status();
print(JSON.stringify(status, null, 2));
if (status.defaultReplicaSet.status !== 'OK' || Object.values(status.defaultReplicaSet.topology).some(n => n.status !== 'ONLINE')) {
    throw new Error('All three cluster members must be ONLINE');
}
session.runSql('CREATE DATABASE IF NOT EXISTS pubsea');
session.runSql("CREATE USER IF NOT EXISTS 'pubsea'@'%' IDENTIFIED BY ?", [os.getenv('MYSQL_APP_PASSWORD')]);
session.runSql("GRANT ALL PRIVILEGES ON pubsea.* TO 'pubsea'@'%'");
