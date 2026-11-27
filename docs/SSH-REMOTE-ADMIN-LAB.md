# SSH remote administration lab - Windows to Ubuntu Server

This exercise uses the Ubuntu VM already managed by Multipass. It demonstrates key-based SSH administration from Windows PowerShell 5.1 without using a production server.

## 1. Identify the VM

~~~powershell
multipass list
multipass info <vm-name>
~~~

Choose the name of your existing Ubuntu 24.04 VM. The helper uses Multipass machine-readable JSON output to obtain the VM's current state and IPv4 address.

## 2. Configure key-based access

From the repository root:

~~~powershell
.\ops\windows-ssh-lab.ps1 -VMName <vm-name>
~~~

The script:

1. Confirms the VM is running and has an IPv4 address.
2. Checks that TCP port 22 is already reachable; it does not open firewall ports.
3. Creates an Ed25519 key pair in $HOME\.ssh\devops-server-operations-lab when no pair exists. Set a passphrase at the prompt.
4. Copies only the .pub public-key file to the VM using Multipass.
5. Adds the key to the current guest user's ~/.ssh/authorized_keys, preserving any existing entries.
6. Verifies SSH login and collects hostname, user, uptime and root filesystem details.
7. Saves a transcript under evidence/ssh-lab-*.txt.

The private key remains in your Windows profile. The helper does not print, transfer or commit it. It does not change sshd settings, disable password authentication, change UFW, or create a root login.

## 3. Practise remote administration

After the helper succeeds, use the IP address and guest username displayed in its output:

~~~powershell
ssh -i "$HOME\.ssh\devops-server-operations-lab" <guest-user>@<vm-ip>
~~~

Then run these commands inside Ubuntu:

~~~bash
hostnamectl
id
uptime
who
free -h
df -h
ip -brief address
ip route
ss -tulpn
systemctl status ssh --no-pager
journalctl -u ssh --since "30 minutes ago" --no-pager
~~~

Practice explaining:

- What the VM's IP address and default route are.
- Which processes are listening, and on which ports.
- The difference between an SSH authentication failure and a network/port-22 failure.
- How to inspect system services and recent SSH logs.
- Why an SSH key is used instead of repeatedly sending a password.

Exit the SSH session with exit.

## 4. Demonstrate safe key handling

- Keep the private key in your Windows .ssh folder.
- Use a passphrase and never paste the private key into Teams, GitHub, screenshots or chat.
- The public key may be installed on this one lab VM; do not reuse a learning key on company or production servers.
- Do not enable bridged networking or expose port 22 to your home/public network for this exercise.
- The helper uses the VM's existing network reachability. If TCP/22 is unavailable, inspect the VM with multipass info and check systemctl status ssh from multipass shell; do not disable the firewall as a workaround.

## 5. Evidence for the manager

Keep evidence/ssh-lab-*.txt. During the demo, show the SSH connection and the output of hostnamectl, uptime, free -h, df -h, ip route and ss -tulpn. Do not show private-key contents or any real credentials.
