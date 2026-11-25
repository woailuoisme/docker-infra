#!/usr/bin/env bash
set -euo pipefail

# 遍历所有非模板数据库，统一加载核心扩展并配置环境
# 注意：pg_cron 是全局调度器，只能在 postgresql.conf 指定的 cron.database_name (即 postgres) 中安装

DATABASES=$(psql -XtA -c "SELECT datname FROM pg_database WHERE datistemplate = false;" --username "$POSTGRES_USER" --dbname "postgres")

for db in $DATABASES; do
	echo "Initializing extensions for database: ${db}"

	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<- 'EOSQL'
		-- 性能监控
		CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

		-- 文本模糊检索
		CREATE EXTENSION IF NOT EXISTS pg_trgm;
		CREATE EXTENSION IF NOT EXISTS ltree;
	EOSQL

	# 可选扩展：可能被构建参数 (WITH_*=false) 关闭，装上了才创建
	for ext in postgis vector pgroonga; do
		if psql -XtA -c "SELECT 1 FROM pg_available_extensions WHERE name = '$ext'" --username "$POSTGRES_USER" --dbname "$db" | grep -q 1; then
			psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" -c "CREATE EXTENSION IF NOT EXISTS ${ext} CASCADE;"
		fi
	done

	# pg_cron 仅在 cron.database_name (即 postgres) 中安装
	if [ "$db" = "postgres" ] && psql -XtA -c "SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron'" --username "$POSTGRES_USER" --dbname "postgres" | grep -q 1; then
		psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" -c "CREATE EXTENSION IF NOT EXISTS pg_cron;"
		echo "Extension pg_cron installed in postgres database."
	fi

	echo "Extensions initialized successfully for database: ${db}"
done

echo "All databases extension initialization completed."
