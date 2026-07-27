# PostGIS installer for PostgreSQL 17 + Patroni

本项目用于在 `postgresql17-ha-patroni-etcd` 已安装好的 PostgreSQL 节点上安装
PostGIS 3.4.2。脚本只操作当前节点，不包含 SSH、SCP 或集群分发逻辑；需要在哪个
PostgreSQL 节点安装，就在哪个节点直接执行 `install.sh`。

## 目录

```text
postgis-install/
├── install.sh
├── README.md
├── postgis安装手册.sql
└── packages/               # yum 版本不足时使用的离线源码包
```

## 依赖选择规则

脚本按照 PostGIS 3.4 官方要求检查已启用的 yum 仓库：

| 依赖 | 最低版本 | 选择规则 |
|---|---:|---|
| GEOS | 3.6 | 仓库版本满足时用 `geos-devel` |
| PROJ | 6.1 | 仓库版本满足时用 `proj-devel` |
| LibXML2 | 2.5 | 使用满足要求的系统 RPM |
| JSON-C | 0.9 | 使用满足要求的系统 RPM |
| GDAL | 2.0 | 3.x 更佳；仓库版本不足时源码编译 |
| SFCGAL | 1.3.1 | 1.4.1+ 可使用全部 SFCGAL 功能 |
| protobuf-c | 1.1.0 | 仓库版本不足时同时编译 protobuf |
| LLVM | 6.0 | 仅 PostgreSQL 启用 JIT 时需要 |

`PCRE` 用于 Address Standardizer。`CMake`、`SQLite`、`CGAL` 和 `protobuf`
是源码回退链所需的构建依赖。yum 仓库没有满足版本的 RPM 时，脚本自动使用
`packages/`，因此 EL7 的旧仓库不会被误用；EL8 仓库版本满足时可减少源码编译。

## 使用

在一台与目标节点相同 EL 大版本、相同 CPU 架构且能够访问 yum 仓库的机器上，
可以先下载当前仓库可提供的完整 RPM 依赖闭包：

```bash
sudo bash downloadrpm.sh --check
sudo bash downloadrpm.sh
```

下载结果按系统和架构隔离保存：

```text
packages/rpm/el7/x86_64/
packages/rpm/el8/x86_64/
```

脚本会递归下载依赖，生成 `SHA256SUMS` 和环境清单。GIS RPM 只有达到 PostGIS
3.4 最低版本才会下载；仓库版本过低或不存在时，`install.sh` 继续使用
`packages/` 中对应的源码包。

先做预检，查看 PostgreSQL 路径和 yum 候选版本：

```bash
chmod +x install.sh
sudo ./install.sh --check
```

在当前节点执行安装：

```bash
sudo ./install.sh
```

所有常用路径和参数也集中放在 `install.sh` 开头的 `User configuration`
配置区，可以直接编辑。取值优先级为：

```text
命令行参数或脚本顶部配置
→ postgres 登录环境和 /home/postgres/.pgev
→ 脚本默认值
```

使用 root 执行且 PostgreSQL 路径留空时，脚本会先以 postgres 登录用户查找
`pg_config`，再读取 HA 项目创建的 `.pgev`；仍未找到时才检查
`/home/postgres/pghome`、`/home/postgres/pg`、`/usr/pgsql-17` 等默认路径。

脚本可安全重复执行。每次运行会先检查当前节点实际安装的 CMake、GEOS、PROJ、
GDAL、SFCGAL、protobuf-c、PCRE 和 PostGIS 版本；达到最低要求的组件直接跳过，
只有缺失或版本过低的组件才继续尝试 yum 或 `packages/` 源码。已经安装的基础
构建 RPM 也不会再次调用 yum 安装。

完全不使用 yum 中的 GIS 依赖、强制采用 `packages/`：

```bash
sudo ./install.sh --source-only
```

如果未自动找到 PostgreSQL 17：

```bash
sudo ./install.sh --pg-config /home/postgres/pghome/bin/pg_config
```

默认自动判断当前节点是否为 Patroni Leader。Leader 会在 `postgres` 数据库创建或
升级扩展，Replica 只安装动态库和扩展 SQL 文件。也可以显式控制：

```bash
sudo ./install.sh --database mydb --create-extension
sudo ./install.sh --no-create-extension
```

## 验证

```bash
PG_CONFIG=/home/postgres/pghome/bin/pg_config
test -f "$("$PG_CONFIG" --pkglibdir)/postgis-3.so"
test -f "$("$PG_CONFIG" --sharedir)/extension/postgis.control"
ldd "$("$PG_CONFIG" --pkglibdir)/postgis-3.so" | grep 'not found' && exit 1 || true
```

在已创建扩展的可写数据库中：

```bash
sudo -u postgres /home/postgres/pghome/bin/psql -d postgres \
  -c "SELECT postgis_full_version();"
```
