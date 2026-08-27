#!/bin/bash
set -e

cd ~/code/grafana/packages/grafana-sql
npm run build
npm pack --pack-destination /tmp
cp /tmp/grafana-sql-13.3.0-pre.tgz /tmp/grafana-sql-fixed.tgz

cd ~/code/grafana-postgresql-datasource
rm -rf node_modules/@grafana/sql
mkdir -p node_modules/@grafana/sql
tar -xzf /tmp/grafana-sql-fixed.tgz --strip-components=1 -C node_modules/@grafana/sql
rm -rf node_modules/.cache
npm run build
