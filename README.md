# PostGIS installer for PostgreSQL + Patroni

本项目用于在 `postgresql17-ha-patroni-etcd` 已安装好的 PostgreSQL 节点上安装
PostGIS 3.6。脚本会自动选择 `packages/` 中 3.6 系列最高的稳定版本，不固定补丁
版本；目录中没有 3.6 包且允许联网时，会从 PostGIS 官方稳定源自动发现并下载
当前最高版本。脚本只操作当前节点，不包含 SSH、SCP 或集群分发逻辑；需要在哪个
PostgreSQL 节点安装，就在哪个节点直接执行 `install.sh`。

依赖默认安装到 postgres 家目录下的 `postgis-deps/`，不会覆盖 `/usr/local`
里的系统库。系统中即使已经存在满足版本的 GIS 库，脚本也不会直接链接它；
每次执行都会从 `packages/` 选择满足要求的最高源码版本，重新安装并覆盖
`postgis-deps/` 中的同名文件。脚本不会先删除整个目录，避免运行中的 PostgreSQL
在重装期间突然找不到动态库。若本地没有合格源码，再从对应项目的官方稳定源下载。可设置
`AUTO_DOWNLOAD=0` 禁止联网下载。

## 目录

```text
postgis-install/
├── install.sh
├── README.md
├── postgis安装手册.sql
└── packages/               # yum 版本不足时使用的离线源码包
```

## 依赖选择规则

脚本按照自动选中的 PostGIS 版本检查依赖。PostGIS 3.6 的主要门槛如下：

| 依赖 | 最低版本 | 选择规则 |
|---|---:|---|
| GEOS | 3.8 | 仓库版本满足时用 `geos-devel` |
| PROJ | 6.1 | 仓库版本满足时用 `proj-devel` |
| LibXML2 | 2.5 | 使用满足要求的系统 RPM |
| JSON-C | 0.9 | 使用满足要求的系统 RPM |
| GDAL | 3.0 | 仓库版本不足时源码编译 |
| SFCGAL | 1.4.1 | 要求 CGAL ≥ 5.3；2.2+ 可使用全部 SFCGAL 功能 |
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
所选 PostGIS 最低版本才会下载；仓库版本过低或不存在时，`install.sh` 继续使用
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

如果未自动找到 PostgreSQL：

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
