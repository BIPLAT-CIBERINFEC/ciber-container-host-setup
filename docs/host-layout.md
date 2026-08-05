# Host Layout

The host filesystem is split by responsibility.

## Application Repositories

```text
/opt/container_apps/<APP_NAME>
```

Each application repository is cloned here. Installation commands should be run
from the corresponding application folder.

Examples:

```text
/opt/container_apps/pathocore-web
/opt/container_apps/pathocore-api
/opt/container_apps/mepram-omop-api
```

## Application Logs

```text
/var/log/local/<APP_NAME>/apps
/var/log/local/<APP_NAME>/apache
```

Use `apps` for application/container logs mounted into services when needed.
Use `apache` for reverse-proxy access/error logs when an application deployment
mounts them.

Examples:

```text
/var/log/local/pathocore-web/apps
/var/log/local/pathocore-web/apache
```

## Container Storage

```text
/srv/containers/storage
/srv/containers/containerd
```

Docker should use `/srv/containers/storage` as its `data-root`.
containerd should use `/srv/containers/containerd` as its root.

This avoids filling `/var` with images, layers, snapshots, and container data.

## Bind Mounts

```text
/srv/containers/bind/<APP_NAME>
```

Store application bind mounts here. Typical examples:

- production environment files
- upload folders
- app-specific runtime folders
- files shared with containers

Do not store secrets in git. If a bind-mounted file contains secrets, create it
directly on the host or via a secrets manager.

## Backups

```text
/srv/containers/backup/<APP_NAME>
```

Use this location for temporary database dumps or deployment backups. Do not
commit these files.

## Shared Resources

```text
/srv/containers/shared
```

Shared host resources that are not owned by a single application.
