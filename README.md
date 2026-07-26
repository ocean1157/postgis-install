# PostGIS installer for PostgreSQL 17 + Patroni

本项目用于在 `postgresql17-ha-patroni-etcd` 已安装并正常运行的 EL7/EL8
集群节点上，从源码安装 PostGIS 及其依赖。脚本复用现有 PostgreSQL 17 的
路径、用户和环境，不安装或替换 PostgreSQL。

## 目录

```text
postgis-install/
├── install.sh
├── README.md
├── postgis安装手册.sql
└── packages/               # 所有离线源码依赖包
```

## 使用

PostGIS 的动态库必须存在于每个 PostgreSQL 节点。将本项目放到每个节点，
依次以 root 执行：

```bash
chmod +x install.sh
sudo ./install.sh
```

脚本会自动：

1. 识别 EL7/EL8；
2. 找到 `postgresql17-ha-patroni-etcd` 安装的 PostgreSQL 17 `pg_config`；
3. 从 `packages/` 编译依赖和 PostGIS；
4. 把扩展安装进现有 PostgreSQL 17 的 `pkglibdir` 和 `sharedir`；
5. 执行 `ldconfig`；
6. 仅在 Patroni Leader 上创建/升级 `postgis` 扩展，Replica 跳过 SQL。

建议先做快速检查：

```bash
sudo ./install.sh --check
```

如自动识别不到 PostgreSQL，可显式指定：

```bash
sudo ./install.sh --pg-config /home/postgres/pghome/bin/pg_config
```

指定业务数据库：

```bash
sudo ./install.sh --database mydb
```

查看全部参数：

```bash
./install.sh --help
```

## 验证

在 Leader 上：

```bash
sudo -u postgres /home/postgres/pg/bin/psql -d postgres \
  -c "SELECT postgis_full_version();"
```

在所有节点确认扩展文件使用同一个 PostgreSQL 17 安装目录：

```bash
PG_CONFIG=/home/postgres/pghome/bin/pg_config
test -f "$("$PG_CONFIG" --pkglibdir)/postgis-3.so"
test -f "$("$PG_CONFIG" --sharedir)/extension/postgis.control"
```

注意：源码安装会耗时较长。默认使用全部 CPU，可通过 `JOBS=4` 限制并行度。
