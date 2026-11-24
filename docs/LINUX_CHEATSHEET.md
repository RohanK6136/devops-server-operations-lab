# Linux / Server Operations Cheat Sheet

| Command | Purpose |
|---|---|
| `pwd` | Print current directory |
| `ls -lah` | List files and sizes |
| `whoami` | Current user |
| `id` | User and group IDs |
| `df -h` | Filesystem capacity |
| `free -h` | Memory usage |
| `uptime` | Uptime and load averages |
| `top` | Live process/resource view |
| `ps aux` | Process list |
| `systemctl status nginx` | Service status |
| `sudo systemctl restart nginx` | Restart Nginx |
| `journalctl -u nginx -n 100` | Recent Nginx service logs |
| `ss -tulpn` | Listening sockets |
| `curl -I http://localhost` | Inspect HTTP response headers |
| `chmod` | Change permissions |
| `chown` | Change ownership |
| `ssh user@server-ip` | Connect to remote host |

## Safe practice

- Understand a command before running it with `sudo`.
- Never paste unknown shell scripts into a production server.
- Do not expose SSH to the whole internet without access controls.
- Prefer SSH keys, least-privilege users, updates, firewall rules, and backups.
