#!/bin/bash

# Run Ansible commands remotely on containerized control node
# Usage: ./scripts/remote-ansible.sh [control-server-ip] [ansible-command]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROL_SERVER="$1"
CONTROL_DIR="/opt/ansible-control"

if [ -z "$CONTROL_SERVER" ]; then
    echo -e "${RED}Usage: $0 <control-server-ip> [ansible-command]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 \"ansible digitalocean -m ping\""
    echo "  $0 192.168.1.100 \"ansible-playbook playbooks/deploy.yml\""
    echo "  $0 192.168.1.100 \"ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=staging\""
    echo ""
    echo "Interactive mode (no command):"
    echo "  $0 192.168.1.100"
    exit 1
fi

# Get the rest of the arguments as the command
shift
ANSIBLE_COMMAND="$*"

check_control_node() {
    echo -e "${BLUE}🔍 Checking control node status...${NC}"
    if ! ssh -o ConnectTimeout=5 root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose ps | grep -q ansible-control" 2>/dev/null; then
        echo -e "${RED}❌ Control node is not running on $CONTROL_SERVER${NC}"
        echo "Start it with: ./scripts/deploy-control-node.sh $CONTROL_SERVER start"
        exit 1
    fi
    echo -e "${GREEN}✅ Control node is running${NC}"
}

run_ansible_command() {
    local cmd="$1"
    echo -e "${BLUE}🚀 Running: ${YELLOW}$cmd${NC}"
    echo -e "${BLUE}📍 On control node: $CONTROL_SERVER${NC}"
    
    # Execute the command in the container
    ssh -t root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose exec -T ansible-control bash -c 'cd /ansible && $cmd'"
}

interactive_mode() {
    echo -e "${BLUE}🎛️ Interactive Ansible Control Mode${NC}"
    echo -e "${YELLOW}Control Server: $CONTROL_SERVER${NC}"
    echo -e "${YELLOW}Container: ansible-control-node${NC}"
    echo ""
    echo "Available commands:"
    echo "  ansible digitalocean -m ping                    # Test connectivity"
    echo "  ansible-playbook playbooks/deploy.yml           # Deploy all apps"
    echo "  ansible-playbook playbooks/deploy.yml -e apps_to_deploy=\"app1,app2\""
    echo "  ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=staging"
    echo "  ansible-playbook playbooks/deploy.yml -e mode=rollback"
    echo "  ansible-inventory --list                        # Show inventory"
    echo "  ansible-vault edit group_vars/prod.yml          # Edit config"
    echo ""
    echo -e "${GREEN}Type 'exit' to quit${NC}"
    echo ""
    
    while true; do
        echo -n -e "${BLUE}ansible@$CONTROL_SERVER:${NC} "
        read -r user_command
        
        case "$user_command" in
            "exit"|"quit"|"q")
                echo -e "${GREEN}👋 Goodbye!${NC}"
                break
                ;;
            "")
                continue
                ;;
            "help"|"h")
                echo "Common commands:"
                echo "  ping       - Test server connectivity"
                echo "  deploy     - Deploy all applications"
                echo "  status     - Check deployment status"
                echo "  logs       - View recent deployment logs"
                echo "  inventory  - Show server inventory"
                echo "  vault      - Edit encrypted configuration"
                ;;
            "ping")
                run_ansible_command "ansible digitalocean -m ping"
                ;;
            "deploy")
                run_ansible_command "ansible-playbook playbooks/deploy.yml"
                ;;
            "status")
                run_ansible_command "ansible digitalocean -m shell -a 'cd /opt && find . -name current -type l -exec ls -la {} \;'"
                ;;
            "logs")
                run_ansible_command "ls -la /ansible/logs/"
                ;;
            "inventory")
                run_ansible_command "ansible-inventory --list"
                ;;
            "vault")
                echo -e "${YELLOW}Opening vault editor...${NC}"
                ssh -t root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose exec ansible-control bash -c 'cd /ansible && ansible-vault edit group_vars/prod.yml'"
                ;;
            *)
                run_ansible_command "$user_command"
                ;;
        esac
        echo ""
    done
}

show_quick_commands() {
    echo -e "${BLUE}🔧 Quick Remote Ansible Commands${NC}"
    echo "================================"
    echo ""
    echo -e "${YELLOW}Server Management:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible digitalocean -m ping\""
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible digitalocean -m shell -a 'docker ps'\""
    echo ""
    echo -e "${YELLOW}Application Deployment:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml\""
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml -e apps_to_deploy='rekalled'\""
    echo ""
    echo -e "${YELLOW}Branch Deployments:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=staging\""
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml -e mode=branch -e branch=test -e apps_to_deploy='rekalled'\""
    echo ""
    echo -e "${YELLOW}Rollbacks:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml -e mode=rollback\""
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-playbook playbooks/deploy.yml -e mode=rollback -e apps_to_deploy='rekalled'\""
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-vault edit group_vars/prod.yml\""
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER \"ansible-inventory --list\""
    echo ""
    echo -e "${YELLOW}Interactive Mode:${NC}"
    echo "  ./scripts/remote-ansible.sh $CONTROL_SERVER"
}

# Main execution
check_control_node

if [ -z "$ANSIBLE_COMMAND" ]; then
    # No command provided, enter interactive mode
    interactive_mode
else
    # Command provided, execute it
    case "$ANSIBLE_COMMAND" in
        "help"|"-h"|"--help")
            show_quick_commands
            ;;
        *)
            run_ansible_command "$ANSIBLE_COMMAND"
            ;;
    esac
fi 