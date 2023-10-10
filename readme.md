# ansible-docker-init

This is an example usage of ansible as a docker configuration entrypoint for a legacy application.

Typically non-12-factor, pre 'cloud native' applications end up having [complicated shell scripts](https://github.com/docker-library/postgres/blob/master/docker-entrypoint.sh) acting as glue to allow for configuration injection via environment variables.

Ansible already has good primitives for configuration and templating, so I came up with the idea of running it as an entrypoint - getting rid of as much shell as possible.

The example here is postgres.  By all means, you should use the official images rather than roll your own, but postgres serves as a good application to demonstrate this approach.

If you look at the entrypoint script `init.sh`, you'll see we're essentially doing two things:

```
ansible-playbook configure.yml -e @vars.yml --diff
exec sudo -u postgres postgres -D /var/lib/postgresql/data
```

This runs a playbook, then boots postgres.  Inside playbook `configure.yml` we're doing tasks like `initdb` if postgres hasn't been initialized, templating postgresql.conf, and templating pg_hba.conf.  Some of these tasks run every time the container starts, so that we can modify configuration without recreating the container.

For example, lets look at vars.yml.  Inside we have an `allowed_networks` list:

```
allowed_networks:
  - 10.0.0.0/8
  - 172.16.0.0/12
  - 192.168.0.0/16
```

This list is used in template pg_hba.conf to enable logins from RFC1918 prefixes:

```
{% for network in allowed_networks %}
host	all		all		{{ network }}		md5
{% endfor %}
```

This allows us to add a network and restart the container without rebuilding.  Here I have added `1.2.3.4./32` to the vars:

```
docker stop nifty_cohen
docker start -i nifty_cohen
+ ansible-playbook configure.yml -e @vars.yml --diff

PLAY [localhost] ***************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

...truncated...

TASK [configure pg_hba.conf] ***************************************************
--- before: /var/lib/postgresql/data/pg_hba.conf
+++ after: /root/.ansible/tmp/ansible-local-7q7hnydo4/tmp30z4m3ya/pg_hba.conf
@@ -100,3 +100,4 @@
 host	all		all		10.0.0.0/8		md5
 host	all		all		172.16.0.0/12		md5
 host	all		all		192.168.0.0/16		md5
+host	all		all		1.2.3.4/32		md5

changed: [localhost]

PLAY RECAP *********************************************************************
localhost                  : ok=6    changed=1    unreachable=0    failed=0    skipped=1    rescued=0    ignored=0   

+ exec sudo -u postgres postgres -D /var/lib/postgresql/data
2023-10-10 03:48:09.679 UTC [1] LOG:  starting PostgreSQL 15.4 on x86_64-alpine-linux-musl, compiled by gcc (Alpine 12.2.1_git20220924-r10) 12.2.1 20220924, 64-bit
```

The prefix was added without having to rebuild anything.  There are of course caveats; adding a new feature altogether will require rebuilding and recreating the container, but of course this is fine if we put our data directory on a volume.

While I've kept this demonstration simple, there are many possibilities here.  We can do anything ansible can do - how about inline vault secrets or environment variable retrieval:

```
allowed_networks:
  - 10.0.0.0/8
  - 172.16.0.0/12
  - 192.168.0.0/16

mem_ratio: 0.5

postgres_pass: !vault |
              $ANSIBLE_VAULT;1.1;AES256
              123456789012345678901234567890

initial_admin: {{ lookup('ansible.builtin.env', 'PGUSER') }}
```

## usage

To run the example, jut run `make`:

```
~/git/ansible-docker-init$ make
docker build . --tag pg
Sending build context to Docker daemon  162.3kB
Step 1/6 : from alpine
 ---> 7e01a0d0a1dc
Step 2/6 : run apk add postgresql15 ansible sudo
 ---> Using cache
 ---> 13aa52e66fac
Step 3/6 : copy configure.yml .
 ---> Using cache
 ---> ef8a1b95c50a
Step 4/6 : copy templates .
 ---> Using cache
 ---> 63345f58a42f
Step 5/6 : copy init.sh .
 ---> Using cache
 ---> 61664ce3ca8f
Step 6/6 : entrypoint [ "/bin/ash", "init.sh" ]
 ---> Using cache
 ---> dfea0f63d8d6
Successfully built dfea0f63d8d6
Successfully tagged pg:latest
docker run -v $(pwd)/vars.yml:/vars.yml:ro pg
+ ansible-playbook configure.yml -e @vars.yml --diff
[WARNING]: No inventory was parsed, only implicit localhost is available
[WARNING]: provided hosts list is empty, only localhost is available. Note that
the implicit localhost does not match 'all'

PLAY [localhost] ***************************************************************

TASK [Gathering Facts] *********************************************************
ok: [localhost]

TASK [create db dir] ***********************************************************
ok: [localhost]

TASK [create lock dir] *********************************************************
--- before
+++ after
@@ -1,7 +1,7 @@
 {
-    "group": 0,
-    "mode": "0755",
-    "owner": 0,
+    "group": 70,
+    "mode": "0700",
+    "owner": 70,
     "path": "/run/postgresql",
-    "state": "absent"
+    "state": "directory"
 }

changed: [localhost]

TASK [check if we're bootstrapped] *********************************************
ok: [localhost]

TASK [initialize database] *****************************************************
changed: [localhost]

TASK [configure postgresql.conf] ***********************************************
--- before: /var/lib/postgresql/data/postgresql.conf
+++ after: /root/.ansible/tmp/ansible-local-7qk7uguyg/tmpm92x57ce/postgresql.conf
@@ -124,7 +124,7 @@
 
 # - Memory -
 
-shared_buffers = 128MB			# min 128kB
+shared_buffers = 31970MB	# min 128kB
 					# (change requires restart)
 #huge_pages = try			# on, off, or try
 					# (change requires restart)

changed: [localhost]

TASK [configure pg_hba.conf] ***************************************************
--- before: /var/lib/postgresql/data/pg_hba.conf
+++ after: /root/.ansible/tmp/ansible-local-7qk7uguyg/tmpdgu32e8p/pg_hba.conf
@@ -96,3 +96,7 @@
 local   replication     all                                     trust
 host    replication     all             127.0.0.1/32            trust
 host    replication     all             ::1/128                 trust
+
+host	all		all		10.0.0.0/8		md5
+host	all		all		172.16.0.0/12		md5
+host	all		all		192.168.0.0/16		md5

changed: [localhost]

PLAY RECAP *********************************************************************
localhost                  : ok=7    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

+ exec sudo -u postgres postgres -D /var/lib/postgresql/data
2023-10-10 03:19:11.114 UTC [1] LOG:  starting PostgreSQL 15.4 on x86_64-alpine-linux-musl, compiled by gcc (Alpine 12.2.1_git20220924-r10) 12.2.1 20220924, 64-bit
2023-10-10 03:19:11.114 UTC [1] LOG:  listening on IPv4 address "127.0.0.1", port 5432
2023-10-10 03:19:11.114 UTC [1] LOG:  could not bind IPv6 address "::1": Address not available
2023-10-10 03:19:11.124 UTC [1] LOG:  listening on Unix socket "/run/postgresql/.s.PGSQL.5432"
2023-10-10 03:19:11.126 UTC [199] LOG:  database system was shut down at 2023-10-10 03:19:08 UTC
2023-10-10 03:19:11.129 UTC [1] LOG:  database system is ready to accept connections
```
