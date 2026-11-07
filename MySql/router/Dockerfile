FROM oraclelinux:9-slim

ARG MYSQL_ROUTER_VERSION=26.10.0
RUN curl --fail --silent --show-error --location \
       https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 \
       -o /etc/pki/rpm-gpg/RPM-GPG-KEY-mysql-2025 \
    && printf '%s\n' \
       '[mysql-tools]' \
       'name=Official MySQL Innovation Tools' \
       'baseurl=https://yum.oracle.com/repo/OracleLinux/OL9/MySQL/innovation/tools/community/$basearch/' \
       'enabled=1' \
       'gpgcheck=1' \
       'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-mysql-2025' \
       > /etc/yum.repos.d/mysql-tools.repo \
    && microdnf install -y "mysql-router-community-${MYSQL_ROUTER_VERSION}" \
    && microdnf clean all \
    && mysqlrouter --version

COPY --chmod=755 entrypoint.sh /usr/local/bin/router-entrypoint
EXPOSE 6446 6447
ENTRYPOINT ["/usr/local/bin/router-entrypoint"]
