# Containerized Ansible Control Node

This setup allows you to run your Ansible control node as a Docker container on a DigitalOcean server, making it accessible to GitHub webhooks while keeping your MacBook Pro as your development machine.

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────────┐    ┌─────────────────────┐
│   MacBook Pro   │    │   DigitalOcean      │    │   Target Servers    │
│   (Development) │    │   (Control Node)    │    │   (Applications)    │
│                 │    │                     │    │                     │
│  Configuration ─┼────┤  ┌─────────────────┐│    │  ┌─────────────────┐│
│  Management     │    │  │ Docker Container││    │  │  Your Apps      ││
│  Monitoring     │    │  │ + Ansible       ││────┼─▶│  (rekalled etc) ││
│                 │    │  │ + Webhook       ││    │  └─────────────────┘│
│                 │    │  └─────────────────┘│    │                     │
└─────────────────┘    └─────────────────────┘    └─────────────────────┘
                                ▲
                                │
                         ┌─────────────────┐
                         │ GitHub/GitLab   │
                         │ (Webhooks)      │
                         └─────────────────┘
```

## 🚀 Quick Setup

### 1. Deploy to DigitalOcean Server

From your MacBook Pro, deploy the control node to your existing server:

```bash
# Deploy the containerized control node
./scripts/deploy-control-node.sh YOUR_SERVER_IP deploy

# Example:
./scripts/deploy-control-node.sh 192.168.1.100 deploy
```

This will:

- ✅ Copy all Docker and Ansible files to the server
- ✅ Build the control node container
- ✅ Start the webhook service on port 9000
- ✅ Mount your SSH keys for target server access

### 2. Configure Environment

Edit the environment file on the server:

```bash
# SSH to your server and edit
ssh root@YOUR_SERVER_IP
cd /opt/ansible-control
nano .env

# Update the webhook secret:
WEBHOOK_SECRET=your-super-secure-secret-here
```

### 3. Configure GitHub Webhooks

Add webhook to your repositories:

- **URL:** `http://YOUR_SERVER_IP:9000/webhook`
- **Content-Type:** `application/json`
- **Secret:** Your webhook secret from `.env`
- **Events:** Just push events

## 🔧 Management from MacBook Pro

### Remote Ansible Commands

Run any Ansible command remotely:

```bash
# Test connectivity
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible digitalocean -m ping"

# Deploy applications
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible-playbook playbooks/deploy.yml"

# Deploy specific apps
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible-playbook playbooks/deploy.yml -e apps_to_deploy='rekalled'"

# Branch deployments
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=staging"

# Rollbacks
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible-playbook playbooks/deploy.yml -e mode=rollback"
```

### Interactive Mode

Start an interactive session:

```bash
# Enter interactive mode
./scripts/remote-ansible.sh YOUR_SERVER_IP

# You'll get a prompt:
ansible@YOUR_SERVER_IP: ping
ansible@YOUR_SERVER_IP: deploy
ansible@YOUR_SERVER_IP: ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=test
```

### Control Node Management

```bash
# Check status
./scripts/deploy-control-node.sh YOUR_SERVER_IP status

# View logs
./scripts/deploy-control-node.sh YOUR_SERVER_IP logs

# Restart service
./scripts/deploy-control-node.sh YOUR_SERVER_IP restart

# Update configuration
./scripts/deploy-control-node.sh YOUR_SERVER_IP update

# Shell access
./scripts/deploy-control-node.sh YOUR_SERVER_IP shell
```

## 📊 Monitoring & Health Checks

### Health Endpoints

```bash
# Check control node health
curl http://YOUR_SERVER_IP:9000/health

# View active deployments
curl http://YOUR_SERVER_IP:9000/deployments
```

### Log Files

Logs are persistent and accessible:

```bash
# Webhook logs
./scripts/deploy-control-node.sh YOUR_SERVER_IP logs

# Deployment logs
ssh root@YOUR_SERVER_IP "ls -la /opt/ansible-control/logs/"
```

## 🔐 Security Features

- **Isolated container** - Ansible runs in controlled environment
- **SSH key mounting** - Your SSH keys are securely mounted
- **Webhook signature verification** - All webhooks are HMAC verified
- **No direct exposure** - Target servers don't expose webhook services

## 📁 File Structure

On your DigitalOcean server:

```
/opt/ansible-control/
├── Dockerfile                 # Container definition
├── docker-compose.yml         # Service orchestration
├── webhook_service.py         # Webhook handler
├── requirements.txt           # Python dependencies
├── .env                       # Environment configuration
├── config/                    # Ansible configuration
├── inventory/                 # Server inventory
├── group_vars/                # Application configuration
├── playbooks/                 # Deployment playbooks
├── roles/                     # Ansible roles
├── logs/                      # Persistent logs
└── ssh-keys/                  # Mounted SSH keys
```

## 🔄 Workflow Examples

### Auto-Deployment Workflow

1. **Developer pushes** to `main` branch
2. **GitHub sends webhook** to `http://YOUR_SERVER_IP:9000/webhook`
3. **Container receives webhook** and validates signature
4. **Ansible deploys** to your target servers automatically
5. **You monitor** from MacBook Pro using management scripts

### Manual Deployment from MacBook Pro

```bash
# 1. Test connectivity
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible digitalocean -m ping"

# 2. Deploy specific app and branch
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible-playbook playbooks/deploy.yml -e apps_to_deploy='rekalled' -e mode=branch -e branch=staging"

# 3. Check deployment status
./scripts/deploy-control-node.sh YOUR_SERVER_IP status

# 4. View logs if needed
./scripts/deploy-control-node.sh YOUR_SERVER_IP logs
```

## 🛠️ Troubleshooting

### Container Not Starting

```bash
# Check container status
./scripts/deploy-control-node.sh YOUR_SERVER_IP status

# View detailed logs
ssh root@YOUR_SERVER_IP "cd /opt/ansible-control && docker-compose logs"

# Rebuild container
ssh root@YOUR_SERVER_IP "cd /opt/ansible-control && docker-compose down && docker-compose build --no-cache && docker-compose up -d"
```

### Webhook Not Receiving

```bash
# Test webhook manually
curl -X POST http://YOUR_SERVER_IP:9000/webhook \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: sha256=$(echo -n '{}' | openssl dgst -sha256 -hmac 'your-secret')" \
  -d '{}'

# Check webhook logs
./scripts/deploy-control-node.sh YOUR_SERVER_IP logs
```

### SSH Key Issues

```bash
# Check mounted keys
ssh root@YOUR_SERVER_IP "docker exec ansible-control-node ls -la /ansible/ssh-keys/"

# Test SSH from container
./scripts/remote-ansible.sh YOUR_SERVER_IP "ansible digitalocean -m ping"
```

## 🎯 Benefits of This Setup

- ✅ **Webhook accessibility** - GitHub can reach your control node
- ✅ **Development flexibility** - Manage everything from MacBook Pro
- ✅ **Production reliability** - Control node runs on reliable server
- ✅ **Easy monitoring** - Real-time status and logs
- ✅ **Scalable** - Can manage multiple target servers
- ✅ **Secure** - Isolated container with proper access controls

This setup gives you the best of both worlds - a development-friendly experience on your MacBook Pro with a production-ready control node in the cloud!
