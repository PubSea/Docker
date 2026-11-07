const password = os.getenv('MYSQL_ROOT_PASSWORD');
shell.connect({scheme: 'mysql', user: 'root', password, host: 'mysql-1', port: 3306});
const status = dba.getCluster('pubsea').status();
print(JSON.stringify(status, null, 2));
if (status.defaultReplicaSet.status !== 'OK' || Object.keys(status.defaultReplicaSet.topology).length !== 3 || Object.values(status.defaultReplicaSet.topology).some(n => n.status !== 'ONLINE')) throw new Error('Cluster is not fully healthy');
const app = {scheme: 'mysql', user: 'pubsea', password: os.getenv('MYSQL_APP_PASSWORD'), host: 'mysql-router'};
const writer = mysql.getSession({...app, port: 6446});
const reader = mysql.getSession({...app, port: 6447});
if (writer.runSql('SELECT @@read_only').fetchOne()[0] !== 0) throw new Error('Writer is read-only');
if (reader.runSql('SELECT @@read_only').fetchOne()[0] !== 1) throw new Error('Reader is not a secondary');
writer.runSql('CREATE TABLE IF NOT EXISTS pubsea.cluster_smoke_test (id VARCHAR(64) PRIMARY KEY, value VARCHAR(64))');
const id = String(Date.now());
writer.runSql('INSERT INTO pubsea.cluster_smoke_test VALUES (?, ?)', [id, 'replicated']);
let replicated = false;
for (let attempt = 0; attempt < 30; attempt++) {
    try {
        const row = reader.runSql('SELECT value FROM pubsea.cluster_smoke_test WHERE id=?', [id]).fetchOne();
        if (row && row[0] === 'replicated') { replicated = true; break; }
    } catch (error) { if (error.code !== 1146) throw error; }
    os.sleep(1);
}
if (!replicated) throw new Error('Write was not replicated to reader');
writer.runSql('DELETE FROM pubsea.cluster_smoke_test WHERE id=?', [id]);
print('PASS: three ONLINE members; Router read/write; secondary read; replicated data');
