# SSH Hardening Guide

This guide covers practical SSH hardening steps for the distributed cluster project.
All nodes (master and worker iPhones/devices) should follow these recommendations before
running experiments over a VPN mesh.

> ⚠️ **Safety note:** Always keep a second terminal session open (or a console/recovery path)
> before making changes to SSH configuration. Test the new settings with a fresh connection
> before closing the existing one, to avoid locking yourself out.

---

## 1. Key-Based Authentication Only

Generate an ED25519 key pair on the orchestrator machine:

```bash
ssh-keygen -t ed25519 -C "dist_cluster_orchestrator" -f ~/.ssh/dist_cluster_id
```

Copy the public key to each worker node:

```bash
ssh-copy-id -i ~/.ssh/dist_cluster_id.pub mobile@100.11.22.44   # iPhone A
ssh-copy-id -i ~/.ssh/dist_cluster_id.pub mobile@100.11.22.55   # iPhone B
```

Verify key login works before disabling password auth:

```bash
ssh -i ~/.ssh/dist_cluster_id mobile@100.11.22.44 echo "key login OK"
```

---

## 2. Disable Password Authentication

Edit `/etc/ssh/sshd_config` on each worker node:

```
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM no
PermitRootLogin no
```

Reload the SSH daemon after saving:

```bash
# Linux / Alpine (iSH)
service sshd restart

# systemd-based systems
sudo systemctl reload sshd
```

---

## 3. Restrict SSH to VPN Interface

Bind `sshd` to the VPN interface only so SSH is not exposed on the public interface.
In `/etc/ssh/sshd_config` set:

```
ListenAddress 100.11.22.44   # replace with each node's VPN IP
```

Alternatively, use `Match Address` to restrict accepted clients to the VPN subnet:

```
AllowUsers mobile@100.11.22.*
```

Reload `sshd` after the change.

---

## 4. Non-Root, Least-Privilege User

Create a dedicated user for cluster operations instead of using root:

```bash
# On each worker node
adduser --disabled-password --gecos "" mobile
# Grant only what is needed (e.g., run Python scripts in /app)
chown -R mobile:mobile /app
```

Add the following to `/etc/ssh/sshd_config` to block root login entirely:

```
PermitRootLogin no
AllowUsers mobile
```

---

## 5. Rate Limiting and fail2ban (Optional)

On Linux worker nodes, install `fail2ban` to block brute-force attempts:

```bash
# Debian/Ubuntu
sudo apt-get install -y fail2ban

# Alpine (iSH)
apk add fail2ban
```

Create `/etc/fail2ban/jail.local` with an SSH jail:

```ini
[sshd]
enabled  = true
port     = ssh
maxretry = 5
bantime  = 600
findtime = 120
```

Start and enable the service:

```bash
sudo systemctl enable --now fail2ban
```

For environments without `fail2ban`, use `iptables` recent-match rate limiting:

```bash
# Allow max 4 new SSH connections per minute from a single IP
iptables -A INPUT -p tcp --dport 22 -m state --state NEW \
  -m recent --set --name SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW \
  -m recent --update --seconds 60 --hitcount 5 --name SSH -j DROP
```

---

## 6. Firewall Allow-Listing to VPN Subnet

Only accept SSH traffic from the VPN subnet (`100.11.22.0/24` in these examples).
All other SSH traffic should be dropped:

```bash
# Allow SSH from VPN subnet only
iptables -A INPUT -p tcp --dport 22 -s 100.11.22.0/24 -j ACCEPT
# Drop all other inbound SSH
iptables -A INPUT -p tcp --dport 22 -j DROP
```

Save the rules so they persist across reboots:

```bash
# Debian/Ubuntu
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save

# Alpine (iSH)
/etc/init.d/iptables save
```

---

## 7. Logging and Audit Recommendations

Set SSH log verbosity to `VERBOSE` in `/etc/ssh/sshd_config` to capture key fingerprints
and client connection details:

```
LogLevel VERBOSE
```

Review authentication logs regularly:

```bash
# systemd journal
journalctl -u sshd --since "1 hour ago"

# Traditional syslog (Alpine/iSH)
tail -n 50 /var/log/auth.log
```

For longer-running experiments, rotate and archive SSH logs:

```bash
# Manually archive today's auth log
cp /var/log/auth.log /var/log/auth.log.$(date +%Y%m%d)
> /var/log/auth.log
```

---

## Summary Checklist

- [ ] ED25519 key pair generated and deployed to all worker nodes
- [ ] Password authentication disabled on all nodes
- [ ] `PermitRootLogin no` set on all nodes
- [ ] `ListenAddress` or `AllowUsers` bound to VPN interface/subnet
- [ ] Dedicated `mobile` (non-root) user with minimal privileges
- [ ] `fail2ban` or `iptables` rate limiting configured
- [ ] Firewall rules allow SSH only from VPN subnet
- [ ] `LogLevel VERBOSE` enabled; logs reviewed after each session

mgreen@mykol.com
