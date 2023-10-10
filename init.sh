set -euxo pipefail

ansible-playbook configure.yml -e @vars.yml --diff

exec sudo -u postgres postgres -D /var/lib/postgresql/data
