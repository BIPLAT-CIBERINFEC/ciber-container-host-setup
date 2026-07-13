# RHEL Notes

The automated bootstrap currently targets Debian-like systems using `apt`.

For RHEL-like hosts, the equivalent setup should be implemented separately and
validated with systems/UTIC.

Expected differences:

- package manager: `dnf`
- Apache package/service naming may differ
- SELinux may require explicit policies or labels for bind mounts
- Docker installation may need institutional repositories or Podman-based
  deployment decisions
- firewall management may use `firewalld`

Do not assume Debian commands are safe on RHEL.
